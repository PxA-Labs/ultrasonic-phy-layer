// OFDM constellation data and error-vector-magnitude math (#71).

import 'dart:math' as math;
import 'dart:typed_data';

/// Reference constellations, normalised to unit average symbol energy as in
/// the native modulator (BPSK +/-1, QPSK (+/-1 +/-j)/sqrt(2)).
enum ConstellationScheme {
  bpsk('BPSK', 1),
  qpsk('QPSK', 2),
  qam16('16-QAM', 4);

  final String label;
  final int bitsPerSymbol;

  const ConstellationScheme(this.label, this.bitsPerSymbol);

  /// Scheme for the native `ofdm_modulation` setting (0 = BPSK, 1 = QPSK).
  static ConstellationScheme fromOfdmModulation(int value) =>
      value == 0 ? bpsk : qpsk;

  /// Ideal points as interleaved I/Q pairs.
  Float64List get referencePoints {
    final levels = _levels;
    if (this == bpsk) return Float64List.fromList([-1, 0, 1, 0]);
    final out = Float64List(2 * levels.length * levels.length);
    var o = 0;
    for (final q in levels) {
      for (final i in levels) {
        out[o++] = i;
        out[o++] = q;
      }
    }
    return out;
  }

  List<double> get _levels {
    switch (this) {
      case ConstellationScheme.bpsk:
        return const [-1.0, 1.0];
      case ConstellationScheme.qpsk:
        return const [-math.sqrt1_2, math.sqrt1_2];
      case ConstellationScheme.qam16:
        final s = 1 / math.sqrt(10);
        return [-3 * s, -s, s, 3 * s];
    }
  }

  /// Nearest per-axis level to [v] (hard decision on one axis).
  double _slice(double v, List<double> levels) {
    var best = levels.first;
    for (final l in levels) {
      if ((v - l).abs() < (v - best).abs()) best = l;
    }
    return best;
  }

  /// Nearest ideal point to (i, q) as [i, q].
  List<double> nearest(double i, double q) {
    final levels = _levels;
    if (this == bpsk) return [_slice(i, levels), 0.0];
    return [_slice(i, levels), _slice(q, levels)];
  }
}

/// Decision-directed RMS error vector magnitude of a set of points.
class EvmResult {
  /// RMS EVM as a fraction of the RMS reference amplitude.
  final double rms;

  /// Points the figure was computed over.
  final int count;

  const EvmResult(this.rms, this.count);

  double get percent => rms * 100;

  /// EVM in dB (20 log10 rms); about -SNR for an AWGN channel.
  double get db =>
      rms > 0 ? 20 * math.log(rms) / math.ln10 : double.negativeInfinity;

  /// Computes the EVM of interleaved I/Q [iq] against [scheme], deciding
  /// each point to its nearest ideal point. Returns null for no points.
  ///
  /// EVM = sqrt( sum |x - ref(x)|^2 / sum |ref(x)|^2 ).
  static EvmResult? compute(List<double> iq, ConstellationScheme scheme) {
    final n = iq.length ~/ 2;
    if (n == 0) return null;
    var errPower = 0.0;
    var refPower = 0.0;
    var used = 0;
    for (var k = 0; k < n; k++) {
      final i = iq[2 * k];
      final q = iq[2 * k + 1];
      if (!i.isFinite || !q.isFinite) continue;
      final ref = scheme.nearest(i, q);
      final di = i - ref[0];
      final dq = q - ref[1];
      errPower += di * di + dq * dq;
      refPower += ref[0] * ref[0] + ref[1] * ref[1];
      used++;
    }
    if (used == 0 || refPower <= 0) return null;
    return EvmResult(math.sqrt(errPower / refPower), used);
  }
}

/// Equalized constellation points of one received OFDM frame.
class ConstellationFrame {
  /// Interleaved I/Q pairs.
  final Float32List iq;
  final ConstellationScheme scheme;

  /// Whether the frame passed CRC (false: shown for diagnosis only).
  final bool decoded;
  final DateTime timestamp;

  ConstellationFrame({
    required this.iq,
    required this.scheme,
    required this.decoded,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  int get pointCount => iq.length ~/ 2;

  late final EvmResult? evm = EvmResult.compute(iq, scheme);
}
