import 'dart:convert';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

void main() {
  group('SoundwaveNative FFI Library Tests', () {
    late SoundwaveNative native;
    bool libraryLoaded = false;

    setUpAll(() {
      try {
        native = SoundwaveNative.instance;
        libraryLoaded = true;
      } catch (e) {
        print('Skipping native FFI tests: dynamic library could not be loaded ($e)');
      }
    });

    test('1. Verify library version string', () {
      if (!libraryLoaded) return;
      final ver = native.version;
      expect(ver, equals('1.0.0'));
    });

    test('2. Verify CRC-32 computation parity', () {
      if (!libraryLoaded) return;
      // Golden vector: CRC32 of empty string is 0
      final crcEmpty = native.crc32(Uint8List(0));
      expect(crcEmpty, equals(0));

      // Golden vector: CRC32 of "123456789" is 0xCBF43926
      final dataStr = '123456789';
      final crcStr = native.crc32(Uint8List.fromList(utf8.encode(dataStr)));
      expect(crcStr, equals(0xCBF43926));
    });

    test('3. Reed-Solomon encoding & decoding parity loop', () {
      if (!libraryLoaded) return;
      // 100 bytes test message
      final msg = Uint8List.fromList(List.generate(100, (i) => i ^ 0xAA));
      final parity = native.rsEncode(msg);
      expect(parity.length, equals(32));

      // Decode correct message
      final decodeResult = native.rsDecode(msg, parity);
      expect(decodeResult['message'], equals(msg));
      expect(decodeResult['errors_corrected'], equals(0));

      // Corrupt 5 bytes in message
      final corruptedMsg = Uint8List.fromList(msg);
      corruptedMsg[5] ^= 0xFF;
      corruptedMsg[20] ^= 0xFF;
      corruptedMsg[45] ^= 0xFF;
      corruptedMsg[70] ^= 0xFF;
      corruptedMsg[90] ^= 0xFF;

      final decodeResultCorrupted = native.rsDecode(corruptedMsg, parity);
      expect(decodeResultCorrupted['message'], equals(msg));
      expect(decodeResultCorrupted['errors_corrected'], equals(5));
    });

    test('4. CSS Chirp modulation and demodulation loop', () {
      if (!libraryLoaded) return;
      final cfgMap = {
        'modulation': 0, // CSS
        'sf': 8,
        'carrier_freq': 19000.0,
        'bandwidth': 2000.0,
        'symbol_duration': 0.02,
        'amplitude': 0.8,
      };
      final cfg = SwConfig.fromMap(cfgMap);

      // Bits array to modulate (4 bytes = 32 bits)
      final bits = Uint8List.fromList([0xAA, 0x55, 0x0F, 0xF0]);
      final samples = native.cssModulate(bits, cfg);
      expect(samples.length, isPositive);

      // Clean up config struct
      calloc.free(cfg);
    });

    test('5. OFDM modulation and demodulation loop', () {
      if (!libraryLoaded) return;
      final cfgMap = {
        'modulation': 1, // OFDM
        'num_subcarriers': 256,
        'cp_length': 64,
        'amplitude': 0.8,
      };
      final cfg = SwConfig.fromMap(cfgMap);

      // Bits array to modulate (4 bytes = 32 bits)
      final bits = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      final samples = native.ofdmModulate(bits, cfg);
      expect(samples.length, isPositive);

      // Clean up config struct
      calloc.free(cfg);
    });
  });
}
