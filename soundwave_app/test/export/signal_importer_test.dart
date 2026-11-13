// Unit tests for SignalImporter (#33).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/export/signal_importer.dart';
import 'package:soundwave/export/wav_format.dart';

/// Golden fixture: [seconds] of a 1 kHz tone at half scale, 44.1 kHz mono.
Uint8List goldenToneWav(double seconds) {
  final n = (seconds * 44100).round();
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = 0.5 * sin(2 * pi * 1000 * i / 44100);
  }
  return encodeWav(x);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sw_import_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  group('SignalImporter', () {
    test('golden WAV: sample count = duration x 44100', () async {
      final path = pathOf('tone.wav');
      File(path).writeAsBytesSync(goldenToneWav(1.5));
      final signal = await const SignalImporter().importFile(path);
      expect(signal.name, 'tone.wav');
      expect(signal.samples.length, (1.5 * 44100).round());
      expect(signal.sampleRate, 44100);
      expect(signal.duration, const Duration(milliseconds: 1500));
      expect(signal.channels, 1);
      expect(signal.format, 'WAV PCM 16-bit');
      expect(signal.peak, closeTo(0.5, 1e-3));
      // Spot-check the tone itself.
      final want = 0.5 * sin(2 * pi * 1000 * 11 / 44100);
      expect(signal.samples[11], closeTo(want, 1 / 32768));
    });

    test('importWav returns the samples', () async {
      final path = pathOf('a.wav');
      File(path).writeAsBytesSync(encodeWav([0.25, -0.5, 0.0]));
      final samples = await const SignalImporter().importWav(path);
      expect(samples, [0.25, -0.5, 0.0]);
    });

    test('importRawPcm decodes 16-bit mono', () async {
      final path = pathOf('test.raw');
      // Write 4 samples: 0, 16384, -16384, 32767
      final bytes = ByteData(8);
      bytes.setInt16(0, 0, Endian.little);
      bytes.setInt16(2, 16384, Endian.little);
      bytes.setInt16(4, -16384, Endian.little);
      bytes.setInt16(6, 32767, Endian.little);
      await File(path).writeAsBytes(bytes.buffer.asUint8List());

      const imp = SignalImporter();
      final samples = await imp.importRawPcm(path, 44100);
      expect(samples.length, 4);
      expect(samples[0], closeTo(0.0, 1e-6));
      expect(samples[1], closeTo(0.5, 1e-6));
      expect(samples[2], closeTo(-0.5, 1e-6));
      expect(samples[3], closeTo(1.0, 1e-4));
    });

    test('raw PCM: odd trailing byte ignored, rate taken from caller', () {
      final raw = Uint8List.fromList([0x00, 0x40, 0x00, 0xC0, 0x7F]);
      final s = const SignalImporter().parseRawPcm(
        raw,
        name: 'x.pcm',
        sampleRate: 48000,
      );
      expect(s.samples, [0.5, -0.5]);
      expect(s.sampleRate, 48000);
      expect(s.format, 'Raw PCM 16-bit');
    });

    test('parse() detects WAV by header and raw PCM otherwise', () {
      const imp = SignalImporter();
      final wav = encodeWav([0.5], sampleRate: 22050);
      // A RIFF header wins over a misleading extension.
      final fromWav = imp.parse(wav, name: 'capture.raw');
      expect(fromWav.sampleRate, 22050);
      expect(fromWav.samples, [0.5]);

      final raw = encodePcm16([0.25, -0.25]);
      final fromRaw = imp.parse(raw, name: 'capture.pcm', rawSampleRate: 8000);
      expect(fromRaw.sampleRate, 8000);
      expect(fromRaw.samples, [0.25, -0.25]);

      // A .wav without a valid header is an error, not raw audio.
      expect(
        () => imp.parse(raw, name: 'broken.WAV'),
        throwsFormatException,
      );
    });

    test('float WAV import reports its format', () {
      final wav = encodeWav([0.1, 0.2], format: WavSampleFormat.float32);
      final s = const SignalImporter().parse(wav, name: 'f.wav');
      expect(s.format, 'WAV float 32-bit');
      expect(s.samples[1], closeTo(0.2, 1e-7));
    });

    test('rejects files over the size limit', () async {
      const imp = SignalImporter(maxBytes: 100);
      expect(
        () => imp.parse(Uint8List(101), name: 'big.raw'),
        throwsFormatException,
      );
      final path = pathOf('big.wav');
      File(path).writeAsBytesSync(Uint8List(200));
      await expectLater(imp.importFile(path), throwsFormatException);
    });

    test('peak and duration of an empty signal', () {
      final s = const SignalImporter().parse(encodeWav([]), name: 'e.wav');
      expect(s.samples, isEmpty);
      expect(s.peak, 0.0);
      expect(s.duration, Duration.zero);
    });
  });
}
