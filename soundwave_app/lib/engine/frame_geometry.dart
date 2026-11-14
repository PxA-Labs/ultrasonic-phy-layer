// Frame geometry — how many audio samples a frame occupies for a given modem
// configuration, and the OFDM band plan behind it. Mirrors the native
// modulators (native/src/css/css_modulate.c, native/src/ofdm/ofdm_modulate.c)
// so the RX engine can size its buffers from the active config instead of
// hard-coded constants.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:soundwave/engine/frame_codec.dart';

class FrameGeometry {
  /// Samples occupied by the synchronisation preamble.
  final int preambleSamples;

  /// Samples per data symbol (CSS chirp, or OFDM symbol incl. cyclic prefix).
  final int samplesPerSymbol;

  /// Payload bits carried by one data symbol.
  final int bitsPerSymbol;

  /// Samples after the last symbol (OFDM: the transmit window's fade-out).
  final int tailSamples;

  /// Sample rate the geometry was computed for (Hz).
  final int sampleRate;

  /// Whether frames carry Reed-Solomon parity (affects the minimum length).
  final bool enableRs;

  const FrameGeometry._({
    required this.preambleSamples,
    required this.samplesPerSymbol,
    required this.bitsPerSymbol,
    required this.tailSamples,
    required this.sampleRate,
    required this.enableRs,
  });

  /// Raw PHY bit rate (bit/s): data bits per symbol over the symbol time,
  /// before preamble, CRC and RS overhead. Computed, not measured.
  double get rawBitRate => bitsPerSymbol * sampleRate / samplesPerSymbol;

  /// Defaults match the native modules: a 0 / missing value means "default".
  factory FrameGeometry.fromConfig(Map<String, dynamic> cfg) {
    int intOf(String k, int def) {
      final v = (cfg[k] as num?)?.toInt() ?? 0;
      return v > 0 ? v : def;
    }

    double doubleOf(String k, double def) {
      final v = (cfg[k] as num?)?.toDouble() ?? 0.0;
      return (v.isFinite && v > 0) ? v : def;
    }

    final enableRs = cfg['enable_rs'] as bool? ?? true;
    final sampleRate = intOf('sample_rate', 44100);

    if ((cfg['modulation'] as num?)?.toInt() == 1) {
      final n = intOf('num_subcarriers', 256);
      final cp = intOf('cp_length', n ~/ 8);
      final band = OfdmBand.fromConfig(cfg);
      final data = math.max(band?.dataSubcarriers ?? 0, 1);
      final qpsk = (cfg['ofdm_modulation'] as num?)?.toInt() != 0;
      final symbol = n + cp;
      return FrameGeometry._(
        preambleSamples: 2 * symbol,
        samplesPerSymbol: symbol,
        bitsPerSymbol: data * (qpsk ? 2 : 1),
        tailSamples: cp ~/ 2, // OFDM_WOLA_LEN: last symbol's fade-out
        sampleRate: sampleRate,
        enableRs: enableRs,
      );
    }

    final duration = doubleOf('symbol_duration', 0.02);
    final symbol = math.max((duration * sampleRate + 0.5).floor(), 1);
    return FrameGeometry._(
      preambleSamples: 10 * symbol, // 8 up-chirps + 2 down-chirps
      samplesPerSymbol: symbol,
      bitsPerSymbol: 1,
      tailSamples: 0,
      sampleRate: sampleRate,
      enableRs: enableRs,
    );
  }

  /// Samples needed to carry a frame of [frameBytes] bytes (incl. preamble).
  int samplesForFrameBytes(int frameBytes) {
    final symbols = (frameBytes * 8 + bitsPerSymbol - 1) ~/ bitsPerSymbol;
    return preambleSamples + symbols * samplesPerSymbol + tailSamples;
  }

  /// Shortest valid frame: CRC + 1 payload byte (+ RS parity).
  int get minFrameSamples => samplesForFrameBytes(
      FrameCodec.crcLength + 1 + (enableRs ? FrameCodec.parityLength : 0));

  /// Longest valid frame: CRC + max payload (+ RS parity).
  int get maxFrameSamples => samplesForFrameBytes(FrameCodec.crcLength +
      FrameCodec.maxPayload +
      (enableRs ? FrameCodec.parityLength : 0));

  /// Window handed to frame detection: a full preamble plus margin on both
  /// sides so a preamble straddling the window edge is found next time.
  int get searchWindowSamples => 2 * preambleSamples + 4 * samplesPerSymbol;

  @override
  String toString() =>
      'FrameGeometry(preamble=$preambleSamples, symbol=$samplesPerSymbol, '
      'bits/symbol=$bitsPerSymbol, tail=$tailSamples, rs=$enableRs)';
}

/// OFDM band plan: which FFT bins carry data and pilots. Mirrors
/// `ofdm_layout_compute` in native/src/ofdm/ofdm_modulate.c exactly (same
/// float32 inputs, same double arithmetic and operation order).
///
/// Active subcarriers lie in [carrier - bandwidth/2, carrier + bandwidth/2]
/// with one empty guard bin inside each edge; every 8th active bin (from the
/// first) is a pilot.
class OfdmBand {
  final int firstBin;
  final int lastBin;
  final double binSpacingHz;

  const OfdmBand._(this.firstBin, this.lastBin, this.binSpacingHz);

  int get activeSubcarriers => lastBin - firstBin + 1;
  int get pilotSubcarriers => (activeSubcarriers + 7) ~/ 8;
  int get dataSubcarriers => activeSubcarriers - pilotSubcarriers;

  /// Centre frequencies of the lowest / highest active subcarrier (Hz).
  double get lowestHz => firstBin * binSpacingHz;
  double get highestHz => lastBin * binSpacingHz;

  static double _f32(double v) => (Float32List(1)..[0] = v)[0];

  /// Null if the band does not fit (the native modem rejects such a config).
  static OfdmBand? fromConfig(Map<String, dynamic> cfg) {
    int intOf(String k, int def) {
      final v = (cfg[k] as num?)?.toInt() ?? 0;
      return v > 0 ? v : def;
    }

    double f32Of(String k, double def) {
      final v = _f32((cfg[k] as num?)?.toDouble() ?? 0.0);
      return (v.isFinite && v > 0) ? v : def;
    }

    final n = intOf('num_subcarriers', 256);
    if (n < 16 || n > 4096 || (n & (n - 1)) != 0) return null;
    final fs = _f32(intOf('sample_rate', 44100).toDouble());
    final carrier = f32Of('carrier_freq', 19000.0);
    final bw = f32Of('bandwidth', 2000.0);
    final fLo = carrier - 0.5 * bw;
    final fHi = carrier + 0.5 * bw;
    final df = fs / n;
    if (!(fLo > 0.0) || !(fHi <= 0.5 * fs - df)) return null;
    final kLo = (fLo * n / fs).ceil() + 1;
    final kHi = (fHi * n / fs).floor() - 1;
    if (kLo < 1 || kHi > n ~/ 2 - 1 || kHi - kLo + 1 < 4) return null;
    return OfdmBand._(kLo, kHi, df);
  }
}
