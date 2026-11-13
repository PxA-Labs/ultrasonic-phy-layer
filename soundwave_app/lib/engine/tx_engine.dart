// TX Engine — encodes messages into frames and modulates via native DSP.
// Emits TxMetrics stream for real-time throughput and status tracking.
//
// Short text with ARQ off goes out as a single legacy frame (raw UTF-8, as
// before). Longer text, binary files and anything sent with ARQ on use the
// link layer (link_frame.dart): fragmentation plus optional stop-and-wait ARQ.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/rx_engine.dart' show RxEngine;

class TxEngine {
  final SoundwaveNative? _native;
  final AudioService _audio;
  final Map<String, dynamic> _configMap;
  final bool _useIsolates;

  /// Link-layer address of this device (shared with its RxEngine).
  final int nodeId;

  final StreamController<TxMetrics> _metricsController =
      StreamController<TxMetrics>.broadcast();

  int _totalBytesSent = 0;
  int _framesSent = 0;

  late final ArqSender _arq;

  TxEngine({
    SoundwaveNative? native,
    required AudioService audio,
    required Map<String, dynamic> configMap,
    bool useIsolates = true,
    int? nodeId,
    math.Random? random,
  })  : _native = native,
        _audio = audio,
        _configMap = configMap,
        _useIsolates = useIsolates,
        nodeId = nodeId ?? randomNodeId() {
    _arq = ArqSender(
      nodeId: this.nodeId,
      transmit: transmitPayload,
      responseAllowance: _responseAllowance,
      random: random,
    );
  }

  /// A random non-zero 16-bit link address.
  static int randomNodeId([math.Random? random]) =>
      1 + (random ?? math.Random()).nextInt(0xFFFE);

  SoundwaveNative get native => _native ?? SoundwaveNative.instance;
  Stream<TxMetrics> get metrics => _metricsController.stream;

  /// Progress of fragmented / ARQ transfers.
  Stream<TxTransferProgress> get transfers => _arq.progress;

  int get totalBytesSent => _totalBytesSent;
  int get framesSent => _framesSent;
  int get retransmissions => _arq.retransmissions;

  ArqConfig get arqConfig => ArqConfig.fromMap(_configMap);

  int get _sampleRate {
    final sr = (_configMap['sample_rate'] as num?)?.toInt() ?? 44100;
    return sr > 0 ? sr : 44100;
  }

  Duration _samplesToDuration(int samples) =>
      Duration(microseconds: samples * 1000000 ~/ _sampleRate);

  /// Time from the end of our frame until the peer's reply can be decoded:
  /// the ACK's airtime plus the receiver's decode latency (it retries every
  /// [RxEngine.retryStepSymbols] symbols and needs a search window first).
  Duration _responseAllowance() {
    final g = FrameGeometry.fromConfig(_configMap);
    final ackFrame = FrameCodec.crcLength +
        LinkFrame.headerLength +
        (g.enableRs ? FrameCodec.parityLength : 0);
    return _samplesToDuration(g.samplesForFrameBytes(ackFrame) +
        g.searchWindowSamples +
        (RxEngine.retryStepSymbols + 2) * g.samplesPerSymbol);
  }

  /// Sends [text]. Fits-in-one-frame text without ARQ uses the legacy raw
  /// frame; everything else goes through the link layer.
  Future<void> sendMessage(String text) async {
    final payload = Uint8List.fromList(utf8.encode(text));
    final arq = arqConfig;
    if (!arq.enabled && payload.length <= FrameCodec.maxPayload) {
      await transmitPayload(payload);
      return;
    }
    await _arq.send(LinkMessage.text(text), arq);
  }

  /// Sends binary [data] (up to [LinkMessage.maxContentBytes]) as a file,
  /// fragmented and, if enabled in settings, protected by ARQ.
  Future<void> sendBinary(
    Uint8List data, {
    String fileName = 'data.bin',
    String mimeType = LinkMessage.defaultMime,
  }) =>
      _arq.send(
        LinkMessage.file(data, fileName: fileName, mimeType: mimeType),
        arqConfig,
      );

  /// Feeds an ACK/NACK received by the RX engine to the ARQ sender.
  void onControlFrame(LinkFrame frame) => _arq.onControlFrame(frame);

  /// Transmits an ACK/NACK reply produced by the RX engine.
  Future<void> sendControl(LinkFrame frame) async {
    await transmitPayload(frame.encode());
  }

  /// Aborts the fragmented transfer in progress.
  void cancelTransfer() => _arq.cancel();

  /// Frames, modulates and plays one PHY payload; returns its airtime.
  /// Playback is asynchronous: this returns once the audio is queued.
  Future<Duration> transmitPayload(Uint8List payload) async {
    // [CRC-32][payload][RS parity] — see FrameCodec. Honours enable_rs.
    final frame = FrameCodec(native).encode(
      payload,
      enableRs: _configMap['enable_rs'] as bool? ?? true,
    );

    // Modulate using compute/isolate to prevent UI lag
    final Float32List samples;
    if (_useIsolates) {
      samples = await compute(_modulateTask, {
        'frame': frame,
        'config': _configMap,
      });
    } else {
      final configPtr = SwConfig.fromMap(_configMap);
      try {
        if (_configMap['modulation'] == 1) {
          samples = native.ofdmModulate(frame, configPtr);
        } else {
          samples = native.cssModulate(frame, configPtr);
        }
      } finally {
        calloc.free(configPtr);
      }
    }

    // Enqueue samples to AudioService and play
    final doubleSamples = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      doubleSamples[i] = samples[i];
    }

    await _audio.enqueueForPlayback(doubleSamples);
    await _audio.startPlayback();

    _totalBytesSent += payload.length;
    _framesSent++;
    if (!_metricsController.isClosed) {
      _metricsController.add(TxMetrics(
        bytesSent: payload.length,
        timestamp: DateTime.now(),
      ));
    }
    return _samplesToDuration(samples.length);
  }

  void resetStats() {
    _totalBytesSent = 0;
    _framesSent = 0;
  }
}

// Background modulate task
Float32List _modulateTask(Map<String, dynamic> args) {
  final frame = args['frame'] as Uint8List;
  final configMap = args['config'] as Map<String, dynamic>;

  final configPtr = SwConfig.fromMap(configMap);
  try {
    final nat = SoundwaveNative.instance;
    if (configMap['modulation'] == 1) {
      return nat.ofdmModulate(frame, configPtr);
    } else {
      return nat.cssModulate(frame, configPtr);
    }
  } finally {
    calloc.free(configPtr);
  }
}
