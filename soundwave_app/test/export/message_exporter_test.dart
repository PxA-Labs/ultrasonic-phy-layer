// Unit tests for MessageExporter (#33).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/export/message_exporter.dart';

MessageRecord record(String text, double snr, DateTime t, String mode) {
  return MessageRecord(
    text: text,
    snr: snr,
    timestamp: t,
    bytes: Uint8List.fromList(utf8.encode(text)),
    mode: mode,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 7, 19, 12, 34, 56, 789);
  final t1 = DateTime.utc(2026, 7, 19, 12, 35, 1);
  final t2 = DateTime.utc(2026, 7, 19, 12, 36);
  final messages = [
    record('hello world', 12.3, t0, 'CSS'),
    record('test message', 8.7, t1, 'OFDM'),
    record('say "hi", ok', 15.0, t2, 'CSS'),
  ];
  const exporter = MessageExporter();

  group('MessageRecord', () {
    test('fromDecoded copies the decoded message and adds the mode', () {
      final m = DecodedMessage(
        text: 'abc',
        snr: 4.5,
        timestamp: DateTime(2026),
        rawBytes: Uint8List.fromList([97, 98, 99]),
      );
      final r = MessageRecord.fromDecoded(m, mode: 'OFDM');
      expect(r.text, 'abc');
      expect(r.snr, 4.5);
      expect(r.timestamp, m.timestamp);
      expect(r.bytes, [97, 98, 99]);
      expect(r.mode, 'OFDM');
    });
  });

  group('JSON', () {
    test('three messages: structure, fields and types', () {
      final json = jsonDecode(exporter.toJson(messages)) as List;
      expect(json, hasLength(3));
      for (final e in json) {
        final keys = (e as Map).keys.toSet();
        expect(keys, {'timestamp', 'text', 'snr', 'mode', 'bytes'});
      }
      expect(json[0], {
        'timestamp': '2026-07-19T12:34:56.789Z',
        'text': 'hello world',
        'snr': 12.3,
        'mode': 'CSS',
        'bytes': utf8.encode('hello world'),
      });
      expect(json[1]['mode'], 'OFDM');
      expect(json[2]['text'], 'say "hi", ok');
    });

    test('non-finite SNR is written as null', () {
      final m = record('x', double.nan, DateTime.utc(2026), 'CSS');
      final json = jsonDecode(exporter.toJson([m])) as List;
      expect(json[0]['snr'], isNull);
    });
  });

  group('CSV', () {
    test('header and one row per message', () {
      final lines = exporter.toCsv(messages).split('\r\n');
      expect(lines.first, 'timestamp,text,snr,mode');
      expect(lines[1], '2026-07-19T12:34:56.789Z,"hello world",12.3,CSS');
      expect(lines[2], '2026-07-19T12:35:01.000Z,"test message",8.7,OFDM');
      expect(lines.last, isEmpty); // trailing CRLF
      expect(lines, hasLength(5));
    });

    test('quotes are doubled and commas stay inside the field', () {
      final csv = exporter.toCsv(messages);
      expect(csv, contains('"say ""hi"", ok",15.0,CSS'));
    });

    test('formula-like text is neutralised', () {
      final m = record('=HYPERLINK("x")', 1, DateTime.utc(2026), 'CSS');
      final csv = exporter.toCsv([m]);
      expect(csv, contains(',"\'=HYPERLINK(""x"")",'));
    });
  });

  group('TXT', () {
    test('one "[YYYY-MM-DD HH:mm:ss] text (SNR, mode)" line each', () {
      final local = [
        record('hello world', 12.3, DateTime(2026, 7, 19, 12, 34, 56), 'CSS'),
        record('test message', 8.7, DateTime(2026, 7, 19, 12, 35, 1), 'OFDM'),
      ];
      final lines = exporter.toText(local).trimRight().split('\n');
      expect(lines, [
        '[2026-07-19 12:34:56] hello world (SNR: 12.3 dB, CSS)',
        '[2026-07-19 12:35:01] test message (SNR: 8.7 dB, OFDM)',
      ]);
    });

    test('newlines inside a message do not break the one-line format', () {
      final m = record('a\nb', 3, DateTime(2026, 1, 1), 'CSS');
      const want = '[2026-01-01 00:00:00] a\\nb (SNR: 3.0 dB, CSS)\n';
      expect(exporter.toText([m]), want);
    });
  });

  group('files', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sw_export_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('exportAsJson/Csv/Text write the rendered content', () async {
      final sep = Platform.pathSeparator;
      final j = await exporter.exportAsJson(messages, '${dir.path}${sep}a');
      final c = await exporter.exportAsCsv(messages, '${dir.path}${sep}b');
      final t = await exporter.exportAsText(messages, '${dir.path}${sep}c');
      expect(j.readAsStringSync(), exporter.toJson(messages));
      expect(c.readAsStringSync(), exporter.toCsv(messages));
      expect(t.readAsStringSync(), exporter.toText(messages));
    });

    test('export() names files by format and timestamp', () async {
      final at = DateTime(2026, 7, 19, 12, 34, 56);
      for (final f in ExportFormat.values) {
        final file = await exporter.export(messages, f, dir, now: at);
        final name = file.uri.pathSegments.last;
        expect(name, 'soundwave_messages_20260719_123456.${f.extension}');
        expect(file.readAsStringSync(), exporter.render(messages, f));
      }
      // A second export in the same second gets a suffix.
      const csv = ExportFormat.csv;
      final again = await exporter.export(messages, csv, dir, now: at);
      expect(again.path, endsWith('soundwave_messages_20260719_123456_1.csv'));
      expect(ExportFormat.text.extension, 'txt');
    });

    test('export() creates the directory', () async {
      final nested = Directory('${dir.path}/exports/deeper');
      final file = await exporter.export(messages, ExportFormat.json, nested);
      expect(file.existsSync(), isTrue);
    });
  });
}
