// Golden tests for WAV encoding/parsing and the streaming WavRecorder (#33).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/export/wav_format.dart';
import 'package:soundwave/export/wav_recorder.dart';

const double lsb = 1 / 32768;

String fourCc(Uint8List b, int offset) =>
    String.fromCharCodes(b.sublist(offset, offset + 4));

/// Deterministic test signal covering the full range including both rails.
Float64List testSignal(int n, {int seed = 1}) {
  final rnd = Random(seed);
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    s[i] = rnd.nextDouble() * 2 - 1;
  }
  if (n >= 4) {
    s[0] = 1.0;
    s[1] = -1.0;
    s[2] = 0.0;
    s[3] = 0.5;
  }
  return s;
}

/// Builds a WAV with arbitrary fmt fields and optional extra chunks.
Uint8List customWav({
  required int tag,
  required int channels,
  required int bits,
  required Uint8List data,
  int sampleRate = 44100,
  List<(String, Uint8List)> chunksBefore = const [],
  int? dataSizeField,
  bool extensible = false,
}) {
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) {
    final d = ByteData(4);
    d.setUint32(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  void u16(int v) {
    final d = ByteData(2);
    d.setUint16(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  str('RIFF');
  u32(0); // patched below
  str('WAVE');
  str('fmt ');
  u32(extensible ? 40 : 16);
  u16(extensible ? WavFormatTag.extensible : tag);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  if (extensible) {
    u16(22); // cbSize
    u16(bits); // valid bits
    u32(0); // channel mask
    u16(tag); // sub-format GUID, first two bytes = format tag
    b.add(List.filled(14, 0));
  }
  for (final (id, body) in chunksBefore) {
    str(id);
    u32(body.length);
    b.add(body);
    if (body.length.isOdd) b.addByte(0);
  }
  str('data');
  u32(dataSizeField ?? data.length);
  b.add(data);
  final out = b.toBytes();
  ByteData.sublistView(out).setUint32(4, out.length - 8, Endian.little);
  return out;
}

void main() {
  group('buildWavHeader', () {
    test('writes RIFF, WAVE, fmt and data chunks (44.1 kHz mono)', () {
      final h = buildWavHeader(1000);
      final d = ByteData.sublistView(h);
      expect(h.length, 44);
      expect(fourCc(h, 0), 'RIFF');
      expect(d.getUint32(4, Endian.little), 36 + 1000);
      expect(fourCc(h, 8), 'WAVE');
      expect(fourCc(h, 12), 'fmt ');
      expect(d.getUint32(16, Endian.little), 16);
      expect(d.getUint16(20, Endian.little), 1); // PCM
      expect(d.getUint16(22, Endian.little), 1); // mono
      expect(d.getUint32(24, Endian.little), 44100);
      expect(d.getUint32(28, Endian.little), 44100 * 2);
      expect(d.getUint16(32, Endian.little), 2);
      expect(d.getUint16(34, Endian.little), 16);
      expect(fourCc(h, 36), 'data');
      expect(d.getUint32(40, Endian.little), 1000);
    });

    test('float32 header uses format 3 and 4-byte blocks', () {
      final h = buildWavHeader(
        400,
        sampleRate: 48000,
        format: WavSampleFormat.float32,
      );
      final d = ByteData.sublistView(h);
      expect(d.getUint16(20, Endian.little), WavFormatTag.ieeeFloat);
      expect(d.getUint32(24, Endian.little), 48000);
      expect(d.getUint32(28, Endian.little), 48000 * 4);
      expect(d.getUint16(32, Endian.little), 4);
      expect(d.getUint16(34, Endian.little), 32);
    });

    test('rejects sizes a RIFF header cannot describe', () {
      expect(() => buildWavHeader(-1), throwsRangeError);
      expect(() => buildWavHeader(wavMaxDataLength + 1), throwsRangeError);
      expect(() => buildWavHeader(0, sampleRate: 0), throwsArgumentError);
    });
  });

  group('encode/parse round trip', () {
    test('16-bit PCM preserves every sample within 1 LSB', () {
      final x = testSignal(5000);
      final wav = encodeWav(x);
      expect(wav.length, 44 + 2 * x.length);
      final parsed = parseWav(wav);
      expect(parsed.sampleRate, 44100);
      expect(parsed.channels, 1);
      expect(parsed.bitsPerSample, 16);
      expect(parsed.formatTag, WavFormatTag.pcm);
      expect(parsed.sizeRepaired, isFalse);
      expect(parsed.samples.length, x.length);
      for (var i = 0; i < x.length; i++) {
        expect(parsed.samples[i], closeTo(x[i], lsb), reason: 'sample $i');
      }
      expect(parsed.samples[2], 0.0);
      expect(parsed.samples[3], 0.5);
      expect(parsed.samples[1], -1.0);
    });

    test('16-bit quantisation clips out-of-range values', () {
      expect(pcm16FromDouble(1.0), 32767);
      expect(pcm16FromDouble(2.5), 32767);
      expect(pcm16FromDouble(-1.0), -32768);
      expect(pcm16FromDouble(-3.0), -32768);
      expect(pcm16FromDouble(double.nan), 0);
      expect(pcm16FromDouble(0.25), 8192);
    });

    test('float32 is exact to float precision, keeps sample rate', () {
      final x = testSignal(1000, seed: 3);
      x[10] = 1.75; // floats may exceed full scale
      final parsed = parseWav(
        encodeWav(x, sampleRate: 48000, format: WavSampleFormat.float32),
      );
      expect(parsed.formatTag, WavFormatTag.ieeeFloat);
      expect(parsed.bitsPerSample, 32);
      expect(parsed.sampleRate, 48000);
      for (var i = 0; i < x.length; i++) {
        expect(parsed.samples[i], closeTo(x[i], 1e-7));
      }
    });

    test('duration matches sample count / rate', () {
      final parsed = parseWav(encodeWav(Float64List(44100 * 2)));
      expect(parsed.duration, const Duration(seconds: 2));
    });
  });

  group('parseWav with other encodings', () {
    test('8-bit unsigned PCM', () {
      final data = Uint8List.fromList([128, 255, 0, 192]);
      final p = parseWav(
        customWav(tag: 1, channels: 1, bits: 8, data: data),
      );
      expect(p.samples, [0.0, 127 / 128, -1.0, 0.5]);
    });

    test('24-bit PCM, including negative values', () {
      final d = ByteData(9);
      void put24(int o, int v) {
        d.setUint8(o, v & 0xFF);
        d.setUint8(o + 1, (v >> 8) & 0xFF);
        d.setUint8(o + 2, (v >> 16) & 0xFF);
      }

      put24(0, 4194304); // +0.5
      put24(3, -4194304); // -0.5
      put24(6, -8388608); // -1.0
      final bytes = d.buffer.asUint8List();
      final p = parseWav(
        customWav(tag: 1, channels: 1, bits: 24, data: bytes),
      );
      expect(p.samples, [0.5, -0.5, -1.0]);
    });

    test('32-bit PCM and 64-bit float', () {
      final i32 = ByteData(8);
      i32.setInt32(0, 1073741824, Endian.little); // 0.5
      i32.setInt32(4, -2147483648, Endian.little); // -1.0
      final i32Bytes = i32.buffer.asUint8List();
      final p32 = parseWav(
        customWav(tag: 1, channels: 1, bits: 32, data: i32Bytes),
      );
      expect(p32.samples, [0.5, -1.0]);

      final f64 = ByteData(16);
      f64.setFloat64(0, 0.123456789, Endian.little);
      f64.setFloat64(8, -0.75, Endian.little);
      final f64Bytes = f64.buffer.asUint8List();
      final p64 = parseWav(
        customWav(tag: 3, channels: 1, bits: 64, data: f64Bytes),
      );
      expect(p64.samples, [0.123456789, -0.75]);
    });

    test('stereo is mixed down to mono', () {
      final d = ByteData(8);
      d.setInt16(0, 16384, Endian.little); // L 0.5
      d.setInt16(2, -16384, Endian.little); // R -0.5
      d.setInt16(4, 16384, Endian.little); // L 0.5
      d.setInt16(6, 16384, Endian.little); // R 0.5
      final bytes = d.buffer.asUint8List();
      final p = parseWav(
        customWav(tag: 1, channels: 2, bits: 16, data: bytes),
      );
      expect(p.channels, 2);
      expect(p.samples, [0.0, 0.5]);
    });

    test('WAVE_FORMAT_EXTENSIBLE resolves the sub-format', () {
      final f = ByteData(8);
      f.setFloat32(0, 0.25, Endian.little);
      f.setFloat32(4, -0.25, Endian.little);
      final p = parseWav(
        customWav(
          tag: 3,
          channels: 1,
          bits: 32,
          data: f.buffer.asUint8List(),
          extensible: true,
        ),
      );
      expect(p.formatTag, WavFormatTag.ieeeFloat);
      expect(p.samples, [0.25, -0.25]);
    });

    test('skips LIST and odd-sized chunks before data', () {
      final data = encodePcm16([0.5, -0.5]);
      final p = parseWav(
        customWav(
          tag: 1,
          channels: 1,
          bits: 16,
          data: data,
          chunksBefore: [
            ('LIST', Uint8List.fromList('INFOtest'.codeUnits)),
            ('junk', Uint8List(3)), // odd size, followed by a pad byte
          ],
        ),
      );
      expect(p.samples, [0.5, -0.5]);
    });

    test('recovers an unfinalised recording (size fields left at 0)', () {
      final data = encodePcm16([0.25, 0.5, -0.25]);
      final p = parseWav(
        customWav(tag: 1, channels: 1, bits: 16, data: data, dataSizeField: 0),
      );
      expect(p.sizeRepaired, isTrue);
      expect(p.samples, [0.25, 0.5, -0.25]);
    });

    test('a data size larger than the file is clamped to the file', () {
      final data = encodePcm16([0.25, -0.25]);
      final p = parseWav(
        customWav(
          tag: 1,
          channels: 1,
          bits: 16,
          data: data,
          dataSizeField: 0xFFFFFFFF,
        ),
      );
      expect(p.samples, [0.25, -0.25]);
    });

    test('rejects non-WAV input and unsupported encodings', () {
      expect(() => parseWav(Uint8List(4)), throwsFormatException);
      final avi = Uint8List.fromList('RIFF\x00\x00\x00\x00AVI '.codeUnits);
      expect(() => parseWav(avi), throwsFormatException);
      final adpcm = customWav(tag: 2, channels: 1, bits: 4, data: Uint8List(8));
      expect(() => parseWav(adpcm), throwsFormatException);
      final noData = buildWavHeader(0).sublist(0, 36);
      expect(() => parseWav(noData), throwsFormatException);
    });
  });

  group('WavRecorder', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sw_wav_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('file name follows soundwave_recording_YYYYMMDD_HHmmss.wav', () {
      final name = WavRecorder.fileNameFor(DateTime(2026, 7, 9, 3, 4, 5));
      expect(name, 'soundwave_recording_20260709_030405.wav');
    });

    test('streams chunks to disk and finalises a valid header', () async {
      final rec = WavRecorder();
      final at = DateTime(2026, 7, 19, 12, 34, 56);
      final path = await rec.startRecording(dir, now: at);
      expect(path, endsWith('soundwave_recording_20260719_123456.wav'));
      expect(rec.isRecording, isTrue);
      // The placeholder header is on disk from the start.
      expect(File(path).lengthSync(), 44);

      final x = testSignal(10000, seed: 9);
      // Uneven chunks, added without awaiting (as a stream listener would).
      var i = 0;
      for (final n in [1, 441, 1000, 37, 4096]) {
        rec.addSamples(Float64List.sublistView(x, i, i + n));
        i += n;
      }
      rec.addSamples(Float64List.sublistView(x, i));
      expect(rec.samplesWritten, x.length);

      final file = await rec.stopRecording();
      expect(rec.isRecording, isFalse);
      expect(file.path, path);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, 44 + 2 * x.length);
      final d = ByteData.sublistView(bytes);
      expect(d.getUint32(4, Endian.little), bytes.length - 8);
      expect(d.getUint32(40, Endian.little), 2 * x.length);

      final parsed = parseWav(bytes);
      expect(parsed.sizeRepaired, isFalse);
      expect(parsed.samples.length, x.length);
      for (var k = 0; k < x.length; k++) {
        expect(parsed.samples[k], closeTo(x[k], lsb), reason: 'sample $k');
      }
    });

    test('empty recording is a valid zero-length WAV', () async {
      final rec = WavRecorder(sampleRate: 48000);
      await rec.startRecording(dir);
      final file = await rec.stopRecording();
      final parsed = parseWav(file.readAsBytesSync());
      expect(parsed.samples, isEmpty);
      expect(parsed.sampleRate, 48000);
    });

    test('never overwrites a recording from the same second', () async {
      final at = DateTime(2026, 1, 2, 3, 4, 5);
      final a = WavRecorder();
      final pathA = await a.startRecording(dir, now: at);
      a.addSamples([0.5]);
      await a.stopRecording();
      final b = WavRecorder();
      final pathB = await b.startRecording(dir, now: at);
      await b.stopRecording();
      expect(pathB, isNot(pathA));
      expect(pathB, endsWith('soundwave_recording_20260102_030405_1.wav'));
      expect(parseWav(File(pathA).readAsBytesSync()).samples, [0.5]);
    });

    test('state errors: stop without start, double start', () async {
      final rec = WavRecorder();
      await expectLater(rec.stopRecording, throwsStateError);
      await rec.startRecording(dir);
      await expectLater(() => rec.startRecording(dir), throwsStateError);
      rec.addSamples([0.1, 0.2]);
      await rec.stopRecording();
      // Samples after stop are ignored.
      await rec.addSamples([0.3]);
      expect(rec.samplesWritten, 2);
    });

    test('creates the target directory', () async {
      final nested = Directory('${dir.path}/a/b/recordings');
      final rec = WavRecorder();
      final path = await rec.startRecording(nested);
      await rec.stopRecording();
      expect(File(path).existsSync(), isTrue);
    });
  });
}
