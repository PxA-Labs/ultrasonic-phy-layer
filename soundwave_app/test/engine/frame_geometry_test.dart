// Unit tests for FrameGeometry (pure math; test/native/loopback_test.dart
// checks it against real modulator output lengths).

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';

void main() {
  group('FrameGeometry', () {
    test('CSS: 10 preamble chirps, 1 bit per chirp', () {
      final g = FrameGeometry.fromConfig(
          {'modulation': 0, 'sample_rate': 44100, 'symbol_duration': 0.02});
      expect(g.samplesPerSymbol, 882);
      expect(g.preambleSamples, 8820);
      expect(g.bitsPerSymbol, 1);
      expect(g.samplesForFrameBytes(46), 8820 + 46 * 8 * 882);
    });

    test('OFDM N=256 cp=64 QPSK: 166 bits per symbol', () {
      final g = FrameGeometry.fromConfig({
        'modulation': 1,
        'num_subcarriers': 256,
        'cp_length': 64,
        'ofdm_modulation': 1,
      });
      expect(g.samplesPerSymbol, 320);
      expect(g.preambleSamples, 640);
      expect(g.bitsPerSymbol, 166); // (95 active - 12 pilots) * 2
      expect(g.samplesForFrameBytes(46), 640 + 3 * 320);
    });

    test('BPSK halves the bits per symbol', () {
      final qpsk = FrameGeometry.fromConfig(
          {'modulation': 1, 'num_subcarriers': 512, 'ofdm_modulation': 1});
      final bpsk = FrameGeometry.fromConfig(
          {'modulation': 1, 'num_subcarriers': 512, 'ofdm_modulation': 0});
      expect(qpsk.bitsPerSymbol, 2 * bpsk.bitsPerSymbol);
    });

    test('zero / missing values fall back to native defaults', () {
      final g = FrameGeometry.fromConfig({'modulation': 1});
      expect(g.samplesPerSymbol, 256 + 32); // N=256, cp=N/8
      final css = FrameGeometry.fromConfig({'modulation': 0});
      expect(css.samplesPerSymbol, 882);
    });

    test('min/max frame bounds respect enable_rs', () {
      final rs = FrameGeometry.fromConfig({'modulation': 0});
      final plain =
          FrameGeometry.fromConfig({'modulation': 0, 'enable_rs': false});
      expect(rs.minFrameSamples, rs.samplesForFrameBytes(4 + 1 + 32));
      expect(plain.minFrameSamples, plain.samplesForFrameBytes(4 + 1));
      expect(rs.maxFrameSamples,
          rs.samplesForFrameBytes(4 + FrameCodec.maxPayload + 32));
      expect(rs.searchWindowSamples, greaterThan(rs.preambleSamples));
    });
  });
}
