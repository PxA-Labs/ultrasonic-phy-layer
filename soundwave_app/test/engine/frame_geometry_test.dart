// Unit tests for FrameGeometry (pure math; test/native/loopback_test.dart
// checks it against real modulator output lengths).

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';

void main() {
  group('FrameGeometry', () {
    test('CSS: 10 preamble chirps, SF bits per chirp of 2^SF * D samples', () {
      // B = 2 kHz at 44.1 kHz: D = round(22.05) = 22 samples per chip.
      final g = FrameGeometry.fromConfig({
        'modulation': 0,
        'sample_rate': 44100,
        'sf': 8,
        'bandwidth': 2000.0,
        'symbol_duration': 0.02, // ignored: a CSS symbol lasts 2^SF / B
      });
      expect(g.samplesPerSymbol, 256 * 22);
      expect(g.preambleSamples, 10 * 256 * 22);
      expect(g.bitsPerSymbol, 8);
      expect(g.samplesForFrameBytes(46), (10 + 46) * 256 * 22);
    });

    test('CSS: every SF, B = 4 kHz (D = 11)', () {
      for (var sf = FrameGeometry.minSf; sf <= FrameGeometry.maxSf; sf++) {
        final g = FrameGeometry.fromConfig(
            {'modulation': 0, 'sf': sf, 'bandwidth': 4000.0});
        final n = (1 << sf) * 11;
        expect(g.samplesPerSymbol, n);
        expect(g.bitsPerSymbol, sf);
        expect(g.symbolSeconds, closeTo(n / 44100, 1e-12));
        // Raw rate = SF * B_eff / 2^SF with B_eff = 44100 / 11.
        expect(g.rawBitRate, closeTo(sf * 44100 / 11 / (1 << sf), 1e-9));
        final symbols = (37 * 8 + sf - 1) ~/ sf;
        expect(g.samplesForFrameBytes(37), (10 + symbols) * n);
        expect(g.airtimeSeconds(37), closeTo((10 + symbols) * n / 44100, 1e-9));
      }
    });

    test('CSS: rates grow as SF falls and as B grows (computed)', () {
      double rate(int sf, double b) =>
          FrameGeometry.fromConfig({'modulation': 0, 'sf': sf, 'bandwidth': b})
              .rawBitRate;
      expect(rate(6, 4000), closeTo(375.9, 0.1));
      expect(rate(7, 4000), closeTo(219.3, 0.1));
      expect(rate(8, 2000), closeTo(62.6, 0.1));
      expect(rate(10, 2000), closeTo(19.6, 0.1));
      for (var sf = 6; sf < 10; sf++) {
        expect(rate(sf, 2000), greaterThan(rate(sf + 1, 2000)));
        expect(rate(sf, 4000), greaterThan(rate(sf, 2000)));
      }
      // A 20-byte message with CRC + RS parity, preamble included.
      final g = FrameGeometry.fromConfig({'modulation': 0, 'sf': 7});
      expect(g.payloadBitRate(20), lessThan(g.rawBitRate));
      expect(g.payloadBitRate(20), greaterThan(0));
    });

    test('CSS: out-of-range SF is clamped to the supported 6..10', () {
      expect(
          FrameGeometry.fromConfig({'modulation': 0, 'sf': 12}).bitsPerSymbol,
          10);
      expect(FrameGeometry.fromConfig({'modulation': 0, 'sf': 3}).bitsPerSymbol,
          6);
    });

    test('decode retry step: 32 OFDM symbols, ~0.25 s of CSS chirps', () {
      expect(FrameGeometry.fromConfig({'modulation': 1}).retryStepSymbols, 32);
      // SF8 @ 2 kHz: 128 ms chirps -> 4 (minimum).
      expect(FrameGeometry.fromConfig({'modulation': 0}).retryStepSymbols, 4);
      // SF6 @ 4 kHz: 16 ms chirps -> ceil(0.25 / 0.016) = 16.
      expect(
          FrameGeometry.fromConfig(
              {'modulation': 0, 'sf': 6, 'bandwidth': 4000.0}).retryStepSymbols,
          16);
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
      expect(css.samplesPerSymbol, 256 * 22); // SF8, 2 kHz, 44.1 kHz
      expect(css.bitsPerSymbol, 8);
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
