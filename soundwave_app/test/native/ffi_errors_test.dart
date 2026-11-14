// Error propagation across the FFI boundary (#34, #36): native error codes
// must surface as SwException with the right code, and invalid handles or
// configs must be rejected by the library rather than crash the app.
// Runs only when libsoundwave can be loaded (CI sets SOUNDWAVE_LIB).

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

Map<String, dynamic> ofdmConfig() => {
      'sample_rate': 44100,
      'modulation': 1,
      'sf': 8,
      'num_subcarriers': 256,
      'cp_length': 64,
      'num_pilots': 8,
      'carrier_freq': 19000.0,
      'bandwidth': 2000.0,
      'symbol_duration': 0.02,
      'amplitude': 0.8,
      'ofdm_modulation': 1,
      'threshold': 3.0,
      'equalizer': 0,
      'coding_rate': 0.5,
      'enable_rs': true,
    };

Matcher throwsSw(int code) =>
    throwsA(isA<SwException>().having((e) => e.code, 'code', code));

void main() {
  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping FFI error tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  const badParam = -1;
  const syncError = -4;

  group('FFI error propagation (real library)', () {
    late Pointer<SwConfig> cfg;
    setUp(() => cfg = SwConfig.fromMap(ofdmConfig()));
    tearDown(() => calloc.free(cfg));

    test('CFO estimate on too short a buffer is a sync error', () {
      // Needs two (N + cp) periods: 2 * 320 samples.
      expect(() => native!.estimateCfo(Float32List(639), cfg),
          throwsSw(syncError));
      expect(native!.estimateCfo(Float32List(640), cfg), isA<double>());
    });

    test('an invalid config is rejected by the library', () {
      final bad = SwConfig.fromMap(ofdmConfig()..['amplitude'] = 2.0);
      try {
        expect(() => native!.estimateCfo(Float32List(4096), bad),
            throwsSw(badParam));
        expect(() => native!.audioCaptureStart(bad), throwsSw(badParam));
        expect(() => native!.audioPlaybackStart(bad), throwsSw(badParam));
      } finally {
        calloc.free(bad);
      }
    });

    test('null audio handles are rejected, not dereferenced', () {
      final none = Pointer<Void>.fromAddress(0);
      expect(() => native!.audioCaptureStop(none), throwsSw(badParam));
      expect(() => native!.audioCaptureRead(none, 16), throwsSw(badParam));
      expect(() => native!.audioPlaybackStop(none), throwsSw(badParam));
      expect(() => native!.audioPlaybackWrite(none, Float32List(16)),
          throwsSw(badParam));
    });

    test('SwException carries a readable message for every code', () {
      final messages = <String>{};
      for (final code in [-1, -2, -3, -4, -5, -6, -7]) {
        final e = SwException(code);
        messages.add(e.message);
        expect(e.toString(), contains('code=$code'));
      }
      expect(messages, hasLength(7)); // distinct per code
      expect(SwException(-99).message, contains('-99'));
    });
  }, skip: skip);
}
