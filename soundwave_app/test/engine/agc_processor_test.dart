// AgcProcessor unit tests (mock native AGC).

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/agc_processor.dart';
import 'mock_native.dart';

void main() {
  group('AgcProcessor', () {
    test('applies native gain and reports gain in dB', () {
      final nat = MockSoundwaveNative()
        ..agcLinearGain = 2.0
        ..agcReportedGainDb = 6.0;
      final agc = AgcProcessor(nat);
      final out = agc.process(Float64List.fromList([0.1, -0.2, 0.3]),
          sampleRate: 44100);
      expect(
          out, [closeTo(0.2, 1e-6), closeTo(-0.4, 1e-6), closeTo(0.6, 1e-6)]);
      expect(agc.gainDb, 6.0);
      expect(agc.isActive, isTrue);
      expect(nat.agcCreates, 1);
      agc.dispose();
      expect(nat.agcDestroys, 1);
    });

    test('reuses the instance and recreates it on a sample-rate change', () {
      final nat = MockSoundwaveNative();
      final agc = AgcProcessor(nat);
      for (var i = 0; i < 5; i++) {
        agc.process(Float64List(441), sampleRate: 44100);
      }
      expect(nat.agcCreates, 1);
      agc.process(Float64List(480), sampleRate: 48000);
      expect(nat.agcCreates, 2);
      expect(nat.agcDestroys, 1);
      agc.dispose();
    });

    test('bypasses when the library has no AGC API', () {
      final nat = MockSoundwaveNative()
        ..hasAgc = false
        ..agcLinearGain = 10.0;
      final agc = AgcProcessor(nat);
      final input = Float64List.fromList([0.5, 0.25]);
      expect(identical(agc.process(input, sampleRate: 44100), input), isTrue);
      expect(agc.isActive, isFalse);
      expect(nat.agcProcessCalls, 0);
    });

    test('reset returns the reported gain to 0 dB', () {
      final nat = MockSoundwaveNative();
      final agc = AgcProcessor(nat)
        ..process(Float64List(10), sampleRate: 44100);
      expect(agc.gainDb, 6.0);
      agc.reset();
      expect(agc.gainDb, 0.0);
      expect(nat.agcResets, 1);
      agc.dispose();
    });

    test('empty chunks pass through without creating an instance', () {
      final nat = MockSoundwaveNative();
      final agc = AgcProcessor(nat);
      agc.process(Float64List(0), sampleRate: 44100);
      expect(nat.agcCreates, 0);
    });
  });
}
