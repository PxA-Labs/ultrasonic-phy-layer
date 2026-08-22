// TX Engine — encodes messages into frames and modulates via native DSP.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';

class TxEngine {
  final SoundwaveNative? _native;
  final AudioService _audio;
  final Map<String, dynamic> _configMap;
  final bool _useIsolates;

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

  Future<void> sendMessage(String text) async {
    final payload = Uint8List.fromList(utf8.encode(text));

    // Calculate CRC-32 of payload
    final crc = native.crc32(payload);

    // Frame layout: Prepend CRC-32 (4 bytes, little-endian)
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.little);
    final packet = Uint8List(4 + payload.length);
    packet.setRange(0, 4, crcBytes.buffer.asUint8List());
    packet.setRange(4, packet.length, payload);

    // Apply Reed-Solomon encoding
    final parity = native.rsEncode(packet);
    final frame = Uint8List(packet.length + parity.length);
    frame.setRange(0, packet.length, packet);
    frame.setRange(packet.length, frame.length, parity);

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
