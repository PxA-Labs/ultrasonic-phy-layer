// Radix-2 FFT, analysis windows and dB helpers for the visualizers (#71, #91).
//
// The FFT is iterative and in-place with precomputed twiddle factors and
// bit-reversal table, so one instance can be reused for every frame without
// allocating.

import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 decimation-in-time FFT of a fixed size.
class Fft {
  /// Transform length (a power of two, >= 2).
  final int size;
  final Int32List _bitReverse;
  final Float64List _cos;
  final Float64List _sin;

  Fft._(this.size, this._bitReverse, this._cos, this._sin);

  factory Fft(int size) {
    if (size < 2 || (size & (size - 1)) != 0) {
      throw ArgumentError.value(size, 'size', 'must be a power of two >= 2');
    }
    var bits = 0;
    while ((1 << bits) < size) {
      bits++;
    }
    final rev = Int32List(size);
    for (var i = 0; i < size; i++) {
      var r = 0;
      var v = i;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (v & 1);
        v >>= 1;
      }
      rev[i] = r;
    }
    final half = size ~/ 2;
    final cos = Float64List(half);
    final sin = Float64List(half);
    for (var k = 0; k < half; k++) {
      final a = 2 * math.pi * k / size;
      cos[k] = math.cos(a);
      sin[k] = math.sin(a);
    }
    return Fft._(size, rev, cos, sin);
  }

  /// Forward DFT X[k] = sum x[n] e^(-j 2 pi k n / N), computed in place.
  void transform(Float64List re, Float64List im) {
    if (re.length != size || im.length != size) {
      throw ArgumentError('re and im must both have length $size');
    }
    for (var i = 0; i < size; i++) {
      final j = _bitReverse[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= size; len <<= 1) {
      final half = len >> 1;
      final step = size ~/ len;
      for (var start = 0; start < size; start += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = -_sin[k * step];
          final a = start + k;
          final b = a + half;
          final tr = re[b] * wr - im[b] * wi;
          final ti = re[b] * wi + im[b] * wr;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
  }
}

/// Periodic (DFT-even) Hann window: w[n] = 0.5 - 0.5 cos(2 pi n / N).
///
/// The periodic form is the standard choice for spectral analysis: its
/// coherent gain is exactly 0.5 and a bin-centred tone leaks into exactly
/// its two neighbouring bins.
Float64List hannWindow(int n) {
  if (n <= 0) throw ArgumentError.value(n, 'n', 'must be positive');
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  return w;
}

/// Lowest level reported by [amplitudeToDb] (silence, or a zero bin).
const double kSpectrumFloorDb = -160.0;

/// 20 log10(amplitude), clamped below at [floorDb] (also for 0 or NaN).
double amplitudeToDb(double amplitude, {double floorDb = kSpectrumFloorDb}) {
  if (!(amplitude > 0)) return floorDb;
  final db = 20 * math.log(amplitude) / math.ln10;
  return db < floorDb ? floorDb : db;
}

/// RMS level of [samples] in dBFS (a full-scale square wave reads 0 dBFS).
double rmsDbfs(List<double> samples, {double floorDb = kSpectrumFloorDb}) {
  if (samples.isEmpty) return floorDb;
  var sumSq = 0.0;
  for (final s in samples) {
    sumSq += s * s;
  }
  return amplitudeToDb(math.sqrt(sumSq / samples.length), floorDb: floorDb);
}
