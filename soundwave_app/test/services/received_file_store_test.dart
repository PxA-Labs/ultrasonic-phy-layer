// Received-file saving (#89): untrusted names and no overwriting.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/services/received_file_store.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips directories and unsafe characters', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'C:\Windows\evil.dll'), 'evil.dll');
      expect(sanitizeFileName('..hidden'), 'hidden');
      expect(sanitizeFileName('a:b*c?.txt'), 'a_b_c_.txt');
      expect(sanitizeFileName(''), 'received.bin');
      expect(sanitizeFileName('..'), 'received.bin');
      expect(sanitizeFileName('/'), 'received.bin');
      final long = sanitizeFileName('${'x' * 300}.jpeg');
      expect(long.length, 100);
      expect(long, endsWith('.jpeg'));
    });
  });

  test('mimeTypeForFileName', () {
    expect(mimeTypeForFileName('a.PNG'), 'image/png');
    expect(mimeTypeForFileName('noext'), 'application/octet-stream');
  });

  group('DirectoryFileSink', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sw_rx_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves inside the directory without overwriting', () async {
      final sink = DirectoryFileSink(directory: () async => dir);
      final p1 = await sink.save('../note.txt', Uint8List.fromList([1]));
      final p2 = await sink.save('note.txt', Uint8List.fromList([2]));
      final p3 = await sink.save('note.txt', Uint8List.fromList([3]));
      expect(File(p1).parent.path, dir.path);
      expect(p1, endsWith('note.txt'));
      expect(p2, endsWith('note (1).txt'));
      expect(p3, endsWith('note (2).txt'));
      expect(File(p1).readAsBytesSync(), [1]);
      expect(File(p2).readAsBytesSync(), [2]);
    });
  });
}
