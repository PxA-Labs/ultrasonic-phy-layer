// Constellation reference grids and EVM math (#71).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/constellation.dart';

void main() {
  group('ConstellationScheme', () {
    test('reference grids have the right size and unit energy', () {
      final sizes = {
        ConstellationScheme.bpsk: 2,
        ConstellationScheme.qpsk: 4,
        ConstellationScheme.qam16: 16,
      };
      sizes.forEach((scheme, count) {
        final ref = scheme.referencePoints;
        expect(ref.length, 2 * count, reason: scheme.label);
        var energy = 0.0;
        for (var k = 0; k < ref.length; k += 2) {
          energy += ref[k] * ref[k] + ref[k + 1] * ref[k + 1];
        }
        expect(energy / count, closeTo(1.0, 1e-12), reason: scheme.label);
      });
    });

    test('QPSK points match the native modulator', () {
      const q = 0.70710678;
      final ref = ConstellationScheme.qpsk.referencePoints;
      for (var k = 0; k < ref.length; k++) {
        expect(ref[k].abs(), closeTo(q, 1e-8));
      }
    });

    test('maps the native ofdm_modulation setting', () {
      expect(
          ConstellationScheme.fromOfdmModulation(0), ConstellationScheme.bpsk);
      expect(
          ConstellationScheme.fromOfdmModulation(1), ConstellationScheme.qpsk);
    });

    test('nearest() makes hard decisions', () {
      expect(ConstellationScheme.bpsk.nearest(-0.2, 0.9), [-1.0, 0.0]);
      final q = ConstellationScheme.qpsk.nearest(0.1, -2);
      expect(q[0], closeTo(math.sqrt1_2, 1e-12));
      expect(q[1], closeTo(-math.sqrt1_2, 1e-12));
      final s = 1 / math.sqrt(10);
      final x = ConstellationScheme.qam16.nearest(0.5, -0.1);
      expect(x[0], closeTo(s, 1e-12));
      expect(x[1], closeTo(-s, 1e-12));
    });
  });

  group('EvmResult.compute', () {
    test('ideal points have zero EVM', () {
      for (final scheme in ConstellationScheme.values) {
        final evm = EvmResult.compute(scheme.referencePoints, scheme)!;
        expect(evm.rms, closeTo(0, 1e-12), reason: scheme.label);
        expect(evm.count, scheme.referencePoints.length ~/ 2);
      }
    });

    test('a known error vector gives the expected EVM', () {
      // Every QPSK point displaced by 0.1 (unit-energy reference): 10 %.
      final ref = ConstellationScheme.qpsk.referencePoints;
      final noisy = Float64List(ref.length);
      for (var k = 0; k < ref.length; k += 2) {
        noisy[k] = ref[k] + 0.06;
        noisy[k + 1] = ref[k + 1] - 0.08;
      }
      final evm = EvmResult.compute(noisy, ConstellationScheme.qpsk)!;
      expect(evm.rms, closeTo(0.1, 1e-12));
      expect(evm.percent, closeTo(10, 1e-9));
      expect(evm.db, closeTo(-20, 1e-9));
    });

    test('BPSK quadrature error counts toward EVM', () {
      final evm = EvmResult.compute(
        [1.0, 0.05, -1.0, -0.05],
        ConstellationScheme.bpsk,
      )!;
      expect(evm.rms, closeTo(0.05, 1e-12));
    });

    test('matches the AWGN SNR for Gaussian noise', () {
      // EVM^2 ~ 1/SNR: noise sigma 0.1 per axis -> EVM ~ 0.1 * sqrt(2).
      final rnd = math.Random(5);
      double gauss() {
        final u = 1 - rnd.nextDouble();
        final v = rnd.nextDouble();
        return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
      }

      final ref = ConstellationScheme.qpsk.referencePoints;
      final pts = <double>[];
      for (var n = 0; n < 5000; n++) {
        final k = 2 * rnd.nextInt(4);
        pts.add(ref[k] + 0.1 * gauss());
        pts.add(ref[k + 1] + 0.1 * gauss());
      }
      final evm = EvmResult.compute(pts, ConstellationScheme.qpsk)!;
      expect(evm.rms, closeTo(0.1 * math.sqrt2, 0.006));
    });

    test('empty or non-finite input', () {
      expect(EvmResult.compute([], ConstellationScheme.qpsk), isNull);
      expect(
        EvmResult.compute([double.nan, 0.0], ConstellationScheme.qpsk),
        isNull,
      );
      final evm = EvmResult.compute(
        [double.infinity, 0.0, 1.0, 0.0],
        ConstellationScheme.bpsk,
      )!;
      expect(evm.count, 1);
      expect(evm.rms, 0);
    });
  });

  test('ConstellationFrame exposes point count and EVM', () {
    final frame = ConstellationFrame(
      iq: Float32List.fromList([1, 0, -1, 0, 0.9, 0]),
      scheme: ConstellationScheme.bpsk,
      decoded: true,
    );
    expect(frame.pointCount, 3);
    expect(frame.evm!.count, 3);
    expect(frame.evm!.rms, closeTo(math.sqrt(0.01 / 3), 1e-6));
  });
}
