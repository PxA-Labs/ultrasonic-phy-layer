// Offline decoding of an imported signal through the real RX pipeline.
//
// The samples are streamed in chunks into a private RxEngine via an
// in-memory AudioService, so a file goes through exactly the same AGC,
// frame detection, demodulation and FrameCodec checks as live audio.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../engine/frame_geometry.dart';
import '../engine/rx_engine.dart';
import '../native/soundwave_native.dart';
import '../services/audio_service.dart';

/// Decodes a signal; injectable so UI/state tests need no native library.
typedef SignalDecoder = Future<List<DecodedMessage>> Function(
  Float64List samples,
  Map<String, dynamic> config,
  int sampleRate,
);

class OfflineDecoder {
  /// Samples per chunk pushed into the RX engine (~93 ms at 44.1 kHz).
  static const int chunkSize = 4096;

  /// Runs [samples] through an [RxEngine] configured with [config] (its
  /// `sample_rate` replaced by [sampleRate]) and returns every message that
  /// decodes. Silence is appended so frames ending at the very end of the
  /// file still get their final decode attempt.
  static Future<List<DecodedMessage>> decode(
    Float64List samples,
    Map<String, dynamic> config,
    int sampleRate, {
    SoundwaveNative? native,
  }) async {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    final cfg = Map<String, dynamic>.from(config);
    cfg['sample_rate'] = sampleRate;
    final feed = _FeedAudioService();
    final rx = RxEngine(
      native: native,
      audio: feed,
      configMap: cfg,
      useIsolates: false,
    );
    final got = <DecodedMessage>[];
    final sub = rx.messages.listen(got.add);
    try {
      rx.startListening();
      await feed.listening;

      final g = FrameGeometry.fromConfig(cfg);
      final tail = 2 * RxEngine.retryStepSymbols * g.samplesPerSymbol;
      final total = samples.length + tail;
      final silence = Float64List(chunkSize);
      for (var i = 0; i < total; i += chunkSize) {
        final end = math.min(i + chunkSize, total);
        if (end <= samples.length) {
          feed.push(Float64List.sublistView(samples, i, end));
        } else if (i >= samples.length) {
          feed.push(Float64List.sublistView(silence, 0, end - i));
        } else {
          final mixed = Float64List(end - i);
          mixed.setRange(0, samples.length - i, samples, i);
          feed.push(mixed);
        }
        // Processing is synchronous FFI behind microtasks; a zero timer runs
        // only after the engine has fully handled this chunk.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      rx.stopListening();
      await sub.cancel();
      await feed.close();
    }
    return got;
  }

  /// [decode] on a background isolate (loads the native library there).
  static Future<List<DecodedMessage>> decodeInBackground(
    Float64List samples,
    Map<String, dynamic> config,
    int sampleRate,
  ) {
    final cfg = Map<String, dynamic>.from(config);
    return Isolate.run(() => decode(samples, cfg, sampleRate));
  }
}

/// AudioService whose capture stream is fed programmatically.
class _FeedAudioService implements AudioService {
  _FeedAudioService() {
    _controller = StreamController<Float64List>.broadcast(onListen: _onListen);
  }

  final _listening = Completer<void>();
  late final StreamController<Float64List> _controller;
  bool _capturing = false;

  void _onListen() {
    if (!_listening.isCompleted) _listening.complete();
  }

  Future<void> get listening => _listening.future;

  void push(Float64List chunk) => _controller.add(chunk);

  Future<void> close() => _controller.close();

  @override
  Stream<Float64List> get audioStream => _controller.stream;

  @override
  Future<void> startCapture() async {
    _capturing = true;
  }

  @override
  Future<void> stopCapture() async {
    _capturing = false;
  }

  @override
  bool get isCapturing => _capturing;

  @override
  bool get isPlaying => false;

  @override
  Future<void> startPlayback() async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> enqueueForPlayback(Float64List samples) async {}

  @override
  List<AudioDevice> get inputDevices => const [];

  @override
  List<AudioDevice> get outputDevices => const [];

  @override
  void updateConfig(Map<String, dynamic> config) {}
}
