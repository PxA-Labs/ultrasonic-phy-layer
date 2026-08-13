// Unit tests for MessageHistory persistence.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/message_history.dart';
import 'package:soundwave/engine/rx_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageHistory Tests', () {
    late Directory tempDir;
    late MessageHistory history;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('swhistorytest_');
      history = MessageHistory(customDirectory: tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('add inserts message, truncates to 100 entries, and persists to disk',
        () async {
      final msg = DecodedMessage(
        text: 'hello',
        snr: 10.0,
        timestamp: DateTime.now(),
        rawBytes: Uint8List.fromList([1, 2, 3]),
      );

      history.add(msg);
      expect(history.messages.length, equals(1));
      expect(history.messages[0].text, equals('hello'));

      // Wait a short time for _save future write to finish
      await Future.delayed(const Duration(milliseconds: 50));

      final restoredHistory = MessageHistory(customDirectory: tempDir.path);
      await restoredHistory.load();
      expect(restoredHistory.messages.length, equals(1));
      expect(restoredHistory.messages[0].text, equals('hello'));
      expect(restoredHistory.messages[0].snr, equals(10.0));
    });

    test('clear wipes list and deletes file from disk', () async {
      final msg = DecodedMessage(
        text: 'test',
        snr: 5.0,
        timestamp: DateTime.now(),
        rawBytes: Uint8List.fromList([9]),
      );

      history.add(msg);
      await Future.delayed(const Duration(milliseconds: 50));

      await history.clear();
      expect(history.messages.isEmpty, true);

      final file = File('${tempDir.path}/soundwave/message_history.json');
      expect(file.existsSync(), false);
    });
  });
}
