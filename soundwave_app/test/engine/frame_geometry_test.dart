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

    test('OFDM N=256 cp=64 QPSK, 18-20 kHz: 16 bits per symbol', () {
      final g = FrameGeometry.fromConfig({
        'modulation': 1,
        'num_subcarriers': 256,
        'cp_length': 64,
        'ofdm_modulation': 1,
      });
      expect(g.samplesPerSymbol, 320);
      expect(g.preambleSamples, 640);
      // Bins 106..115 (18.26-19.81 kHz): 10 active, 2 pilots, 8 data.
      expect(g.bitsPerSymbol, 16);
      expect(g.tailSamples, 32); // cp / 2 fade-out after the last symbol
      expect(g.samplesForFrameBytes(46), 640 + 23 * 320 + 32);
      expect(g.rawBitRate, closeTo(16 * 44100 / 320, 1e-9)); // 2205 bit/s
    });

    test('OFDM band plan mirrors ofdm_layout_compute', () {
      OfdmBand? band(int n, double fc, double bw) => OfdmBand.fromConfig({
            'num_subcarriers': n,
            'carrier_freq': fc,
            'bandwidth': bw,
            'sample_rate': 44100,
          });
      final d = band(256, 19000, 2000)!;
      expect([d.firstBin, d.lastBin], [106, 115]);
      expect([d.pilotSubcarriers, d.dataSubcarriers], [2, 8]);
      expect(d.lowestHz, greaterThan(18000));
      expect(d.highestHz, lessThan(20000));
      expect(band(512, 19000, 2000)!.dataSubcarriers, 19);
      expect(band(1024, 19000, 2000)!.dataSubcarriers, 39);
      expect(band(2048, 19000, 2000)!.dataSubcarriers, 79);
      expect(band(256, 19500, 3000)!.dataSubcarriers, 13);
      // Defaults (0 / missing) = 19 kHz +- 1 kHz.
      expect(OfdmBand.fromConfig({})!.firstBin, 106);
      // Rejected like the native band check.
      expect(band(256, 21500, 2000), isNull, reason: 'above Nyquist');
      expect(band(256, 21000, 2000), isNull, reason: 'no guard below Nyquist');
      expect(band(256, 19000, 500), isNull, reason: 'too few subcarriers');
      expect(band(256, 500, 2000), isNull, reason: 'reaches DC');
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
