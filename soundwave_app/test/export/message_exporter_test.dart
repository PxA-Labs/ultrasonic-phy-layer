// Unit tests for MessageExporter

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/export/message_exporter.dart';

void main() {
  group('MessageExporter', () {
    final messages = [
      DecodedMessage(text: 'hello', snr: 12.5, timestamp: DateTime(2026, 7, 19), rawBytes: Uint8List(0)),
      DecodedMessage(text: 'world', snr: 8.2, timestamp: DateTime(2026, 7, 19, 1), rawBytes: Uint8List(0)),
    ];

    test('export as JSON', () async {
      final dir = Directory.systemTemp.createTempSync('swtest_');
      final path = '${dir.path}test.json';
      final file = await MessageExporter().exportAsJson(messages, path);
      expect(file.existsSync(), true);
      final json = jsonDecode(await file.readAsString()) as List;
      expect(json.length, 2);
      expect(json[0]['text'], 'hello');
      expect(json[0]['snr'], 12.5);
      dir.deleteSync(recursive: true);
    });

    test('export as CSV', () async {
      final dir = Directory.systemTemp.createTempSync('swtest_');
      final path = '${dir.path}test.csv';
      final file = await MessageExporter().exportAsCsv(messages, path);
      expect(file.existsSync(), true);
      final csv = await file.readAsString();
      expect(csv, contains('timestamp,text,snr,mode'));
      expect(csv, contains('hello,12.5,CSS'));
      dir.deleteSync(recursive: true);
    });

    test('export as text', () async {
      final dir = Directory.systemTemp.createTempSync('swtest_');
      final path = '${dir.path}test.txt';
      final file = await MessageExporter().exportAsText(messages, path);
      expect(file.existsSync(), true);
      final text = await file.readAsString();
      expect(text, contains('hello (SNR: 12.5 dB)'));
      expect(text, contains('world (SNR: 8.2 dB)'));
      dir.deleteSync(recursive: true);
    });
  });
}
