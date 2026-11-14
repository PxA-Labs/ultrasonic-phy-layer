// Unit tests for storage layout, rolling capture buffer and signal samples.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/export/message_exporter.dart';
import 'package:soundwave/export/signal_sample_store.dart';
import 'package:soundwave/export/soundwave_storage.dart';
import 'package:soundwave/export/wav_format.dart';

void main() {
  late Directory base;
  late SoundwaveStorage storage;

  setUp(() {
    base = Directory.systemTemp.createTempSync('sw_storage_');
    storage = SoundwaveStorage(baseDirectory: () async => base);
  });
  tearDown(() => base.deleteSync(recursive: true));

  group('SoundwaveStorage', () {
    test('creates soundwave/<area> directories', () async {
      for (final area in StorageArea.values) {
        final dir = await storage.directory(area);
        expect(dir.existsSync(), isTrue);
        final sep = Platform.pathSeparator;
        expect(dir.path, endsWith('soundwave$sep${area.folder}'));
      }
    });

    test('reports usage per area and in total', () async {
      final rec = await storage.directory(StorageArea.recordings);
      final exp = await storage.directory(StorageArea.exports);
      File('${rec.path}/a.wav').writeAsBytesSync(Uint8List(100));
      File('${rec.path}/b.wav').writeAsBytesSync(Uint8List(50));
      File('${exp.path}/c.csv').writeAsBytesSync(Uint8List(7));
      expect(await storage.usageBytes(StorageArea.recordings), 150);
      expect(await storage.usageBytes(StorageArea.exports), 7);
      expect(await storage.usageBytes(StorageArea.samples), 0);
      expect(await storage.usageBytes(), 157);
    });

    test('usage of a missing root is zero', () async {
      expect(await storage.usageBytes(), 0);
    });

    test('clear deletes only its area and honours keep', () async {
      final rec = await storage.directory(StorageArea.recordings);
      final exp = await storage.directory(StorageArea.exports);
      final keep = File('${rec.path}/active.wav');
      keep.writeAsBytesSync(Uint8List(10));
      File('${rec.path}/old.wav').writeAsBytesSync(Uint8List(10));
      File('${exp.path}/log.txt').writeAsStringSync('x');

      final n = await storage.clear(
        StorageArea.recordings,
        keep: {keep.path},
      );
      expect(n, 1);
      expect(keep.existsSync(), isTrue);
      expect(File('${rec.path}/old.wav').existsSync(), isFalse);
      expect(File('${exp.path}/log.txt').existsSync(), isTrue);
      expect(await storage.clear(StorageArea.exports), 1);
      expect(await storage.usageBytes(StorageArea.exports), 0);
    });

    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('RollingSampleBuffer', () {
    test('keeps the newest samples in order', () {
      final b = RollingSampleBuffer(5);
      expect(b.isEmpty, isTrue);
      b.add([1, 2, 3]);
      expect(b.snapshot(), [1, 2, 3]);
      b.add([4, 5, 6, 7]);
      expect(b.length, 5);
      expect(b.snapshot(), [3, 4, 5, 6, 7]);
      b.add([8, 9, 10, 11, 12, 13, 14]); // larger than capacity
      expect(b.snapshot(), [10, 11, 12, 13, 14]);
      b.clear();
      expect(b.snapshot(), isEmpty);
    });

    test('rejects a non-positive capacity', () {
      expect(() => RollingSampleBuffer(0), throwsArgumentError);
    });
  });

  group('SignalSampleStore', () {
    test('writes WAV plus JSON sidecar with message metadata', () async {
      final samples = Float64List.fromList([0.5, -0.25, 0.0, 0.125]);
      final message = MessageRecord(
        text: 'hello',
        snr: 11.5,
        timestamp: DateTime.utc(2026, 7, 19, 12),
        bytes: Uint8List.fromList(utf8.encode('hello')),
        mode: 'OFDM',
      );
      final at = DateTime(2026, 7, 19, 12, 0, 5);
      final saved = await SignalSampleStore(storage).save(
        samples,
        sampleRate: 44100,
        note: 'kitchen, 2 m',
        message: message,
        now: at,
      );
      final dir = await storage.directory(StorageArea.samples);
      expect(saved.wav.parent.path, dir.path);
      expect(saved.wav.path, endsWith('signal_20260719_120005.wav'));
      expect(saved.metadata.path, endsWith('signal_20260719_120005.json'));

      final wav = parseWav(saved.wav.readAsBytesSync());
      expect(wav.samples, samples);
      expect(wav.sampleRate, 44100);

      final meta = jsonDecode(saved.metadata.readAsStringSync()) as Map;
      expect(meta['note'], 'kitchen, 2 m');
      expect(meta['file'], 'signal_20260719_120005.wav');
      expect(meta['sample_rate'], 44100);
      expect(meta['samples'], 4);
      expect(meta['snr'], 11.5);
      expect(meta['decoded_text'], 'hello');
      expect(meta['mode'], 'OFDM');
      expect(meta['timestamp'], at.toUtc().toIso8601String());
      expect((meta['message'] as Map)['bytes'], utf8.encode('hello'));
    });

    test('works without a message and never overwrites', () async {
      final store = SignalSampleStore(storage);
      final at = DateTime(2026, 1, 1);
      final a = await store.save(
        Float64List.fromList([0.5]),
        sampleRate: 8000,
        now: at,
      );
      final b = await store.save(
        Float64List.fromList([0.25]),
        sampleRate: 8000,
        now: at,
      );
      expect(b.wav.path, isNot(a.wav.path));
      expect(b.wav.path, endsWith('signal_20260101_000000_1.wav'));
      final meta = jsonDecode(a.metadata.readAsStringSync()) as Map;
      expect(meta['decoded_text'], isNull);
      expect(meta['snr'], isNull);
      expect(parseWav(a.wav.readAsBytesSync()).samples, [0.5]);
    });

    test('rejects an empty sample buffer', () async {
      await expectLater(
        SignalSampleStore(storage).save(Float64List(0), sampleRate: 44100),
        throwsArgumentError,
      );
    });
  });
}
