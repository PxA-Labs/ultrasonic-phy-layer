import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('TestToneGenerator Tests', () {
    test('1. Generate Sine Wave', () {
      final samples = TestToneGenerator.generateSine(440.0, 1.0, 44100.0);
      expect(samples.length, equals(44100));

      // Sine wave peak amplitude check
      double maxVal = 0.0;
      for (final s in samples) {
        if (s.abs() > maxVal) maxVal = s.abs();
      }
      expect(maxVal, closeTo(1.0, 0.01));
    });

    test('2. Generate Linear Chirp (LFM)', () {
      final samples = TestToneGenerator.generateChirp(
        18000.0,
        20000.0,
        0.5,
        44100.0,
      );
      expect(samples.length, equals(22050));
    });

    test('3. Generate Silence', () {
      final samples = TestToneGenerator.generateSilence(0.5, 44100.0);
      expect(samples.length, equals(22050));
      for (final s in samples) {
        expect(s, equals(0.0));
      }
    });
  });

  group('WavUtility Header Validation Tests', () {
    test('1. Create WAV from float samples and verify header layout', () {
      // 100 samples
      final floatSamples = Float64List.fromList(
        List.generate(100, (i) => (i % 10 - 5) / 5.0),
      );
      final wavBytes = WavUtility.createWav(floatSamples, 44100);

      // Total size must be 44 header bytes + 200 data bytes (2 bytes per sample) = 244 bytes
      expect(wavBytes.length, equals(244));

      final byteData = ByteData.view(wavBytes.buffer);

      // RIFF check
      final riff = String.fromCharCodes(wavBytes.sublist(0, 4));
      expect(riff, equals('RIFF'));

      // Chunk size check: 36 + data size = 236
      final chunkSize = byteData.getUint32(4, Endian.little);
      expect(chunkSize, equals(236));

      // WAVE check
      final wave = String.fromCharCodes(wavBytes.sublist(8, 12));
      expect(wave, equals('WAVE'));

      // fmt chunk check
      final fmt = String.fromCharCodes(wavBytes.sublist(12, 16));
      expect(fmt, equals('fmt '));

      final formatCode = byteData.getUint16(20, Endian.little);
      expect(formatCode, equals(1)); // PCM

      final channels = byteData.getUint16(22, Endian.little);
      expect(channels, equals(1)); // Mono

      final sampleRate = byteData.getUint32(24, Endian.little);
      expect(sampleRate, equals(44100));

      final bitsPerSample = byteData.getUint16(34, Endian.little);
      expect(bitsPerSample, equals(16));

      // data chunk check
      final dataHeader = String.fromCharCodes(wavBytes.sublist(36, 40));
      expect(dataHeader, equals('data'));

      final dataSize = byteData.getUint32(40, Endian.little);
      expect(dataSize, equals(200));
    });
  });

  group('RecordAudioService Lifecycle Checks', () {
    test('1. Basic status fields getter verification', () {
      final service = RecordAudioService();
      expect(service.isCapturing, isFalse);
      expect(service.isPlaying, isFalse);
      expect(service.inputDevices.first.name, contains('Microphone'));
      expect(service.outputDevices.first.name, contains('Speaker'));
    });
  });
}
