// Signal importer — loads WAV or raw PCM files for offline processing.

import 'dart:io';
import 'dart:typed_data';

class SignalImporter {
  Future<Float64List> importWav(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final data = bytes.buffer.asByteData();
    // Skip 44-byte WAV header, read as 16-bit mono
    final sampleCount = (bytes.length - 44) ~/ 2;
    final samples = Float64List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final int16 = data.getInt16(44 + i * 2, Endian.little);
      samples[i] = int16 / 32768.0;
    }
    return samples;
  }

  Future<Float64List> importRawPcm(String path, int sampleRate) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final sampleCount = bytes.length ~/ 2;
    final samples = Float64List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final int16 = (bytes[i * 2] | (bytes[i * 2 + 1] << 8)).toSigned(16);
      samples[i] = int16 / 32768.0;
    }
    return samples;
  }
}
