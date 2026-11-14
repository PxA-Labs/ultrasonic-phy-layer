// Runs the monitor's spectrum analysis off the UI isolate (issue #91).
//
// [IsolateSpectrumPipeline] keeps one long-lived worker isolate that owns a
// [SpectrumAnalyzer]. Audio chunks go to the worker as transferable buffers
// and spectra come back the same way, so neither direction copies sample
// data. At most one batch is in flight; while the worker is busy, new audio
// is coalesced into a bounded backlog, and the analyzer's maxFramesPerPush
// keeps only the newest frames of a large batch. A slow device therefore
// computes fewer spectra (the display stays current) instead of queueing
// work without bound.
//
// [InlineSpectrumPipeline] runs the same analyzer synchronously, for
// platforms without isolates (web) and for deterministic widget tests.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'spectrum_analyzer.dart';

/// Spectra produced from one or more audio chunks, oldest first.
class SpectrumBatch {
  final List<Float64List> frames;

  /// Frames skipped since the previous batch (load shedding).
  final int skipped;

  const SpectrumBatch(this.frames, {this.skipped = 0});
}

/// Analyzer settings shared by both pipelines.
class SpectrumConfig {
  final int fftSize;
  final int hopSize;
  final double sampleRate;
  final int maxFramesPerPush;

  const SpectrumConfig({
    required this.fftSize,
    required this.sampleRate,
    int? hopSize,
    this.maxFramesPerPush = 8,
  }) : hopSize = hopSize ?? fftSize ~/ 2;

  int get binCount => fftSize ~/ 2 + 1;
  double get binWidthHz => sampleRate / fftSize;
  double get secondsPerFrame => hopSize / sampleRate;

  SpectrumAnalyzer createAnalyzer() => SpectrumAnalyzer(
        fftSize: fftSize,
        hopSize: hopSize,
        sampleRate: sampleRate,
        maxFramesPerPush: maxFramesPerPush,
      );
}

abstract class SpectrumPipeline {
  SpectrumConfig get config;

  /// Spectra as they are computed.
  Stream<SpectrumBatch> get batches;

  /// Frames skipped so far to keep up (see the file comment).
  int get skippedFrames;

  /// Queues [samples] for analysis. Never blocks the caller.
  void add(Float64List samples);

  /// Drops buffered audio, e.g. after a pause. Results of audio added
  /// before the reset are discarded.
  void reset();

  Future<void> dispose();

  /// The isolate pipeline where isolates exist, otherwise inline.
  static SpectrumPipeline preferred(SpectrumConfig config) =>
      kIsWeb ? InlineSpectrumPipeline(config) : IsolateSpectrumPipeline(config);
}

class InlineSpectrumPipeline implements SpectrumPipeline {
  @override
  final SpectrumConfig config;
  final SpectrumAnalyzer _analyzer;
  // Synchronous: a spectrum is delivered before add() returns, as when the
  // analyzer was called directly.
  final StreamController<SpectrumBatch> _out =
      StreamController<SpectrumBatch>.broadcast(sync: true);
  int _reportedSkipped = 0;

  InlineSpectrumPipeline(this.config) : _analyzer = config.createAnalyzer();

  @override
  Stream<SpectrumBatch> get batches => _out.stream;

  @override
  int get skippedFrames => _analyzer.skippedFrames;

  @override
  void add(Float64List samples) {
    if (_out.isClosed) return;
    final frames = _analyzer.addSamples(samples);
    final skipped = _analyzer.skippedFrames - _reportedSkipped;
    _reportedSkipped = _analyzer.skippedFrames;
    if (frames.isNotEmpty || skipped > 0) {
      _out.add(SpectrumBatch(frames, skipped: skipped));
    }
  }

  @override
  void reset() => _analyzer.reset();

  @override
  Future<void> dispose() => _out.close();
}

class IsolateSpectrumPipeline implements SpectrumPipeline {
  @override
  final SpectrumConfig config;

  /// Most audio kept while the worker is busy: one FFT window plus enough
  /// hops for one full push. Older samples are dropped.
  final int maxBacklogSamples;

  final StreamController<SpectrumBatch> _out =
      StreamController<SpectrumBatch>.broadcast();
  final ReceivePort _fromWorker = ReceivePort();
  final List<Float64List> _pending = [];
  int _pendingSamples = 0;
  Isolate? _isolate;
  SendPort? _toWorker;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;
  int _skipped = 0;
  int _droppedSamples = 0;

  IsolateSpectrumPipeline(this.config, {int? maxBacklogSamples})
      : maxBacklogSamples = maxBacklogSamples ??
            config.fftSize + config.hopSize * config.maxFramesPerPush {
    _fromWorker.listen(_onMessage);
    Isolate.spawn(
      _workerMain,
      _WorkerInit(_fromWorker.sendPort, config),
      debugName: 'soundwave-spectrum',
      errorsAreFatal: false,
    ).then((iso) {
      if (_disposed) {
        iso.kill(priority: Isolate.immediate);
      } else {
        _isolate = iso;
      }
    }, onError: (Object e, StackTrace st) {
      if (!_out.isClosed) _out.addError(e, st);
    });
  }

  @override
  Stream<SpectrumBatch> get batches => _out.stream;

  @override
  int get skippedFrames => _skipped;

  /// Samples dropped from the backlog while the worker was busy.
  int get droppedSamples => _droppedSamples;

  @override
  void add(Float64List samples) {
    if (_disposed || samples.isEmpty) return;
    _pending.add(samples);
    _pendingSamples += samples.length;
    _trimBacklog();
    _pump();
  }

  void _trimBacklog() {
    while (_pendingSamples > maxBacklogSamples && _pending.isNotEmpty) {
      final excess = _pendingSamples - maxBacklogSamples;
      final head = _pending.first;
      if (head.length <= excess) {
        _pending.removeAt(0);
        _pendingSamples -= head.length;
        _droppedSamples += head.length;
      } else {
        _pending[0] = Float64List.sublistView(head, excess);
        _pendingSamples -= excess;
        _droppedSamples += excess;
      }
    }
  }

  void _pump() {
    final port = _toWorker;
    if (port == null || _inFlight || _pending.isEmpty) return;
    final chunk = Float64List(_pendingSamples);
    var o = 0;
    for (final p in _pending) {
      chunk.setRange(o, o + p.length, p);
      o += p.length;
    }
    _pending.clear();
    _pendingSamples = 0;
    _inFlight = true;
    port.send(_Work(
      _generation,
      TransferableTypedData.fromList([chunk]),
    ));
  }

  void _onMessage(Object? message) {
    if (_disposed) return;
    if (message is SendPort) {
      _toWorker = message;
      _pump();
      return;
    }
    if (message is _Result) {
      _inFlight = false;
      if (message.generation == _generation) {
        _skipped += message.skipped;
        final frames = _unpack(message);
        if (frames.isNotEmpty || message.skipped > 0) {
          _out.add(SpectrumBatch(frames, skipped: message.skipped));
        }
      }
      _pump();
    }
  }

  List<Float64List> _unpack(_Result r) {
    if (r.frameCount == 0) return const [];
    final flat = r.data.materialize().asFloat64List();
    final bins = config.binCount;
    return [
      for (var f = 0; f < r.frameCount; f++)
        Float64List.sublistView(flat, f * bins, (f + 1) * bins),
    ];
  }

  @override
  void reset() {
    if (_disposed) return;
    _generation++;
    _pending.clear();
    _pendingSamples = 0;
    _toWorker?.send(_Reset(_generation));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker.close();
    await _out.close();
  }
}

class _WorkerInit {
  final SendPort replies;
  final SpectrumConfig config;
  const _WorkerInit(this.replies, this.config);
}

class _Work {
  final int generation;
  final TransferableTypedData samples;
  const _Work(this.generation, this.samples);
}

class _Reset {
  final int generation;
  const _Reset(this.generation);
}

class _Result {
  final int generation;
  final int frameCount;
  final int skipped;
  final TransferableTypedData data;
  const _Result(this.generation, this.frameCount, this.skipped, this.data);
}

void _workerMain(_WorkerInit init) {
  final inbox = ReceivePort();
  init.replies.send(inbox.sendPort);
  final analyzer = init.config.createAnalyzer();
  final bins = init.config.binCount;
  var generation = 0;
  inbox.listen((Object? message) {
    if (message is _Reset) {
      generation = message.generation;
      analyzer.reset();
      return;
    }
    if (message is! _Work) return;
    if (message.generation != generation) {
      // Audio from before a reset: drop it, but answer so the sender's
      // in-flight slot is released.
      init.replies.send(_Result(message.generation, 0, 0,
          TransferableTypedData.fromList(const <TypedData>[])));
      return;
    }
    final samples = message.samples.materialize().asFloat64List();
    final before = analyzer.skippedFrames;
    final frames = analyzer.addSamples(samples);
    final flat = Float64List(frames.length * bins);
    for (var f = 0; f < frames.length; f++) {
      flat.setRange(f * bins, (f + 1) * bins, frames[f]);
    }
    init.replies.send(_Result(
      generation,
      frames.length,
      analyzer.skippedFrames - before,
      TransferableTypedData.fromList([flat]),
    ));
  });
}
