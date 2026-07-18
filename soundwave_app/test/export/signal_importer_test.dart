// Unit tests for SignalImporter (requires WAV fixtures)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/export/signal_importer.dart';

void main() {
  group('SignalImporter', () {
    test('importRawPcm decodes 16-bit mono', () async {
      final dir = Directory.systemTemp.createTempSync('swtest_');
      final path = '${dir.path}test.raw';
      // Write 4 samples: 0, 16384, -16384, 32767
      final bytes = ByteData(8);
      bytes.setInt16(0, 0, Endian.little);
      bytes.setInt16(2, 16384, Endian.little);
      bytes.setInt16(4, -16384, Endian.little);
      bytes.setInt16(6, 32767, Endian.little);
      await File(path).writeAsBytes(bytes.buffer.asUint8List());

      final imp = SignalImporter();
      final samples = await imp.importRawPcm(path, 44100);
      expect(samples.length, 4);
      expect(samples[0], closeTo(0.0, 1e-6));
      expect(samples[1], closeTo(0.5, 1e-6));
      expect(samples[2], closeTo(-0.5, 1e-6));
      expect(samples[3], closeTo(1.0, 1e-6));
      dir.deleteSync(recursive: true);
    });
  });
}
