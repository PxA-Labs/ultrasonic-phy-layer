// Frame geometry — how many audio samples a frame occupies for a given modem
// configuration. Mirrors the native modulators (native/src/css/css_modulate.c,
// native/src/ofdm/ofdm_modulate.c) so the RX engine can size its buffers from
// the active config instead of hard-coded constants.

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

  /// Whether frames carry Reed-Solomon parity (affects the minimum length).
  final bool enableRs;

  /// Audio sample rate (Hz) the geometry was computed for.
  final int sampleRate;

  /// New audio (in symbols) the RX engine waits for between two decode
  /// attempts of a pending frame.
  final int retryStepSymbols;

  /// Supported CSS spreading factors (native CSS_MIN_SF..CSS_MAX_SF).
  static const int minSf = 6;
  static const int maxSf = 10;

  /// Native CSS defaults (css_geometry in native/src/css/css_modulate.c).
  static const int defaultSf = 8;
  static const double defaultCssBandwidth = 2000.0;

  /// OFDM decode-retry step; CSS waits ~0.25 s (4..32 chirps).
  static const int ofdmRetryStepSymbols = 32;

  const FrameGeometry._({
    required this.preambleSamples,
    required this.samplesPerSymbol,
    required this.bitsPerSymbol,
    required this.enableRs,
    required this.sampleRate,
    required this.retryStepSymbols,
  });

  /// CSS samples per chip, D = round(fs / B) with B as the float32 the
  /// native sw_config_t stores. The effective bandwidth is fs / D.
  static int cssSamplesPerChip(int sampleRate, double bandwidth) {
    final b = Float32List.fromList([bandwidth])[0];
    return math.max(1, (sampleRate / b).round());
  }

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
        sampleRate: sampleRate,
        retryStepSymbols: ofdmRetryStepSymbols,
      );
    }

    // CSS: each chirp carries SF bits (2^SF chips of D samples); preamble is
    // 8 up-chirps + 2 down-chirps. Mirrors css_geometry() / css_modulate.c.
    final sf = math.min(maxSf, math.max(minSf, intOf('sf', defaultSf)));
    final d = cssSamplesPerChip(
        sampleRate, doubleOf('bandwidth', defaultCssBandwidth));
    final symbol = (1 << sf) * d;
    final quarterSecond = (0.25 * sampleRate / symbol).ceil();
    final retry = math.min(ofdmRetryStepSymbols, math.max(4, quarterSecond));
    return FrameGeometry._(
      preambleSamples: 10 * symbol,
      samplesPerSymbol: symbol,
      bitsPerSymbol: sf,
      enableRs: enableRs,
      sampleRate: sampleRate,
      retryStepSymbols: retry,
    );
  }

  /// Duration of one data symbol in seconds.
  double get symbolSeconds => samplesPerSymbol / sampleRate;

  /// Raw PHY bit rate while data symbols are on air (no preamble, no FEC).
  double get rawBitRate => bitsPerSymbol * sampleRate / samplesPerSymbol;

  /// Air time of a frame of [frameBytes] bytes, preamble included.
  double airtimeSeconds(int frameBytes) =>
      samplesForFrameBytes(frameBytes) / sampleRate;

  /// Payload throughput of back-to-back single frames carrying
  /// [payloadBytes] each (CRC + RS parity and preamble counted as overhead).
  double payloadBitRate(int payloadBytes) {
    final frame = FrameCodec.crcLength +
        payloadBytes +
        (enableRs ? FrameCodec.parityLength : 0);
    return payloadBytes * 8 / airtimeSeconds(frame);
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
