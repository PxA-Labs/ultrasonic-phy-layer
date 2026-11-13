// TX Engine — encodes messages into frames and modulates via native DSP.
// Emits TxMetrics stream for real-time throughput and status tracking.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'package:soundwave/engine/frame_codec.dart';

class TxEngine {
  final SoundwaveNative? _native;
  final AudioService _audio;
  final Map<String, dynamic> _configMap;
  final bool _useIsolates;

  final StreamController<TxMetrics> _metricsController =
      StreamController<TxMetrics>.broadcast();

  int _totalBytesSent = 0;
  int _framesSent = 0;

  TxEngine({
    SoundwaveNative? native,
    required AudioService audio,
    required Map<String, dynamic> configMap,
    bool useIsolates = true,
  })  : _native = native,
        _audio = audio,
        _configMap = configMap,
        _useIsolates = useIsolates;

  SoundwaveNative get native => _native ?? SoundwaveNative.instance;
  Stream<TxMetrics> get metrics => _metricsController.stream;

  int get totalBytesSent => _totalBytesSent;
  int get framesSent => _framesSent;

  Future<void> sendMessage(String text) async {
    final payload = Uint8List.fromList(utf8.encode(text));
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
