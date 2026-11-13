// Frame geometry — how many audio samples a frame occupies for a given modem
// configuration. Mirrors the native modulators (native/src/css/css_modulate.c,
// native/src/ofdm/ofdm_modulate.c) so the RX engine can size its buffers from
// the active config instead of hard-coded constants.

import 'dart:math' as math;

import 'package:soundwave/engine/frame_codec.dart';

class FrameGeometry {
  /// Samples occupied by the synchronisation preamble.
  final int preambleSamples;

  /// Samples per data symbol (CSS chirp, or OFDM symbol incl. cyclic prefix).
  final int samplesPerSymbol;

  /// Payload bits carried by one data symbol.
  final int bitsPerSymbol;

  /// Whether frames carry Reed-Solomon parity (affects the minimum length).
  final bool enableRs;

  const FrameGeometry._({
    required this.preambleSamples,
    required this.samplesPerSymbol,
    required this.bitsPerSymbol,
    required this.enableRs,
  });

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
      final active = n ~/ 2 - n ~/ 8 - 1;
      final pilots = (active + 7) ~/ 8;
      final data = math.max(active - pilots, 1);
      final qpsk = (cfg['ofdm_modulation'] as num?)?.toInt() != 0;
      final symbol = n + cp;
      return FrameGeometry._(
        preambleSamples: 2 * symbol,
        samplesPerSymbol: symbol,
        bitsPerSymbol: data * (qpsk ? 2 : 1),
        enableRs: enableRs,
      );
    }

    final duration = doubleOf('symbol_duration', 0.02);
    final symbol = math.max((duration * sampleRate + 0.5).floor(), 1);
    return FrameGeometry._(
      preambleSamples: 10 * symbol, // 8 up-chirps + 2 down-chirps
      samplesPerSymbol: symbol,
      bitsPerSymbol: 1,
      enableRs: enableRs,
    );
  }

  /// Samples needed to carry a frame of [frameBytes] bytes (incl. preamble).
  int samplesForFrameBytes(int frameBytes) {
    final symbols = (frameBytes * 8 + bitsPerSymbol - 1) ~/ bitsPerSymbol;
    return preambleSamples + symbols * samplesPerSymbol;
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
      'bits/symbol=$bitsPerSymbol, rs=$enableRs)';
}
