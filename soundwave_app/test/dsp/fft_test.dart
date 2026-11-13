// FFT, window and dB helper correctness (#71, #91).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/fft.dart';

/// Reference O(N^2) DFT.
(Float64List, Float64List) naiveDft(List<double> re, List<double> im) {
  final n = re.length;
  final outRe = Float64List(n);
  final outIm = Float64List(n);
  for (var k = 0; k < n; k++) {
    var sr = 0.0;
    var si = 0.0;
    for (var t = 0; t < n; t++) {
      final a = -2 * math.pi * k * t / n;
      sr += re[t] * math.cos(a) - im[t] * math.sin(a);
      si += re[t] * math.sin(a) + im[t] * math.cos(a);
    }
    outRe[k] = sr;
    outIm[k] = si;
  }
  return (outRe, outIm);
}

void main() {
  group('Fft', () {
    test('matches a naive DFT on random complex input', () {
      final rnd = math.Random(71);
      for (final n in [2, 4, 8, 64, 256]) {
        final re = Float64List.fromList(
          List.generate(n, (_) => rnd.nextDouble() * 2 - 1),
        );
        final im = Float64List.fromList(
          List.generate(n, (_) => rnd.nextDouble() * 2 - 1),
        );
        final (refRe, refIm) = naiveDft(re, im);
        Fft(n).transform(re, im);
        for (var k = 0; k < n; k++) {
          expect(re[k], closeTo(refRe[k], 1e-9), reason: 'n=$n k=$k re');
          expect(im[k], closeTo(refIm[k], 1e-9), reason: 'n=$n k=$k im');
        }
      }
    });

    test('a bin-centred cosine lands in exactly two mirrored bins', () {
      const n = 256;
      const bin = 37;
      final re = Float64List.fromList(
        List.generate(n, (t) => math.cos(2 * math.pi * bin * t / n)),
      );
      final im = Float64List(n);
      Fft(n).transform(re, im);
      for (var k = 0; k < n; k++) {
        final mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
        final expected = (k == bin || k == n - bin) ? n / 2 : 0.0;
        expect(mag, closeTo(expected, 1e-9), reason: 'k=$k');
      }
    });

    test('an impulse has a flat spectrum', () {
      const n = 64;
      final re = Float64List(n)..[0] = 1;
      final im = Float64List(n);
      Fft(n).transform(re, im);
      for (var k = 0; k < n; k++) {
        expect(re[k], closeTo(1, 1e-12));
        expect(im[k], closeTo(0, 1e-12));
      }
    });

    test('preserves energy (Parseval)', () {
      const n = 512;
      final rnd = math.Random(3);
      final re = Float64List.fromList(
        List.generate(n, (_) => rnd.nextDouble() - 0.5),
      );
      final timeEnergy = re.fold(0.0, (s, v) => s + v * v);
      final im = Float64List(n);
      Fft(n).transform(re, im);
      var freqEnergy = 0.0;
      for (var k = 0; k < n; k++) {
        freqEnergy += re[k] * re[k] + im[k] * im[k];
      }
      expect(freqEnergy / n, closeTo(timeEnergy, 1e-9));
    });

    test('rejects sizes that are not powers of two', () {
      expect(() => Fft(0), throwsArgumentError);
      expect(() => Fft(1), throwsArgumentError);
      expect(() => Fft(100), throwsArgumentError);
      expect(() => Fft(8).transform(Float64List(4), Float64List(8)),
          throwsArgumentError);
    });
  });

  group('hannWindow', () {
    test('is periodic Hann: zero start, unit peak, symmetric, sum N/2', () {
      const n = 1024;
      final w = hannWindow(n);
      expect(w.length, n);
      expect(w[0], 0.0);
      expect(w[n ~/ 2], closeTo(1.0, 1e-15));
      for (var i = 1; i < n; i++) {
        expect(w[i], closeTo(w[n - i], 1e-12), reason: 'i=$i');
      }
      expect(w.fold(0.0, (s, v) => s + v), closeTo(n / 2, 1e-9));
    });

    test('rejects non-positive lengths', () {
      expect(() => hannWindow(0), throwsArgumentError);
    });
  });

  group('dB scaling', () {
    test('amplitudeToDb', () {
      expect(amplitudeToDb(1.0), closeTo(0.0, 1e-12));
      expect(amplitudeToDb(0.5), closeTo(-6.0206, 1e-4));
      expect(amplitudeToDb(10.0), closeTo(20.0, 1e-12));
      expect(amplitudeToDb(1e-3), closeTo(-60.0, 1e-9));
      expect(amplitudeToDb(0.0), kSpectrumFloorDb);
      expect(amplitudeToDb(double.nan), kSpectrumFloorDb);
      expect(amplitudeToDb(1e-20), kSpectrumFloorDb);
      expect(amplitudeToDb(1e-3, floorDb: -40), -40);
    });

    test('rmsDbfs of a full-scale sine is -3.01 dBFS', () {
      final sine = List.generate(4410, (i) => math.sin(2 * math.pi * i / 441));
      expect(rmsDbfs(sine), closeTo(-3.0103, 1e-3));
      expect(rmsDbfs(const []), kSpectrumFloorDb);
      expect(rmsDbfs(List.filled(10, 0.0)), kSpectrumFloorDb);
    });
  });
}
