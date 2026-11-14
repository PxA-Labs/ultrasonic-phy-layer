// Frame geometry — how many audio samples a frame occupies for a given modem
// configuration, and the OFDM band plan behind it. Mirrors the native
// modulators (native/src/css/css_modulate.c, native/src/ofdm/ofdm_modulate.c)
// so the RX engine can size its buffers from the active config instead of
// hard-coded constants.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/native/soundwave_native.dart' show SoundwaveNative;

class FrameGeometry {
  /// Samples occupied by the synchronisation preamble.
  final int preambleSamples;

  /// Samples per data symbol (CSS chirp, or OFDM symbol incl. cyclic prefix).
  final int samplesPerSymbol;

  /// Payload bits carried by one data symbol.
  final int bitsPerSymbol;

  /// Samples after the last symbol (OFDM: the transmit window's fade-out).
  final int tailSamples;

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
    required this.tailSamples,
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
      final band = OfdmBand.fromConfig(cfg);
      final data = math.max(band?.dataSubcarriers ?? 0, 1);
      final qpsk = (cfg['ofdm_modulation'] as num?)?.toInt() != 0;
      final symbol = n + cp;
      return FrameGeometry._(
        preambleSamples: 2 * symbol,
        samplesPerSymbol: symbol,
        bitsPerSymbol: data * (qpsk ? 2 : 1),
        tailSamples: cp ~/ 2, // OFDM_WOLA_LEN: last symbol's fade-out
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
      tailSamples: 0,
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
    return preambleSamples + symbols * samplesPerSymbol + tailSamples;
  }

  /// Shortest valid frame: CRC + 1 payload byte (+ RS parity).
  int get minFrameSamples => samplesForFrameBytes(
      FrameCodec.crcLength + 1 + (enableRs ? FrameCodec.parityLength : 0));

  /// Longest valid frame: CRC + max payload (+ RS parity).
  int get maxFrameSamples => samplesForFrameBytes(FrameCodec.crcLength +
      FrameCodec.maxPayload +
      (enableRs ? FrameCodec.parityLength : 0));

  /// Airtime the TX path aims for per frame. Long frames are fragile (one
  /// noise burst or a moved phone loses the whole frame), stall ARQ (each
  /// attempt waits a frame's airtime) and give no progress feedback. 15 s
  /// keeps OFDM frames full (219-byte payloads take ~1 s) and only splits
  /// slow CSS settings (a full frame is ~34 s at SF8 and ~110 s at SF10,
  /// 2 kHz; the latter does not even fit [SoundwaveNative.maxFrameSamples]).
  static const double targetFrameAirtimeSeconds = 15.0;

  int _frameBytes(int payload) =>
      FrameCodec.crcLength + payload + (enableRs ? FrameCodec.parityLength : 0);

  /// Sample budget for one transmitted frame that must carry at least
  /// [minPayload] bytes: [targetFrameAirtimeSeconds], stretched to twice the
  /// smallest such frame when that alone takes more than half of it, and
  /// never above [SoundwaveNative.maxFrameSamples]. The stretch matters for
  /// slow CSS settings (SF10 / 2 kHz: a 12-byte link frame already takes
  /// ~25 s, mostly preamble and FEC): frames there stay at most twice the
  /// minimum, so at least half of their airtime carries payload.
  int txFrameSampleBudget({int minPayload = 1}) {
    final smallest = samplesForFrameBytes(_frameBytes(minPayload));
    final target = (targetFrameAirtimeSeconds * sampleRate).floor();
    return math.min(
        SoundwaveNative.maxFrameSamples, math.max(target, 2 * smallest));
  }

  /// Largest payload (at most [FrameCodec.maxPayload]) whose frame takes no
  /// more than [maxSamples] samples; 0 if not even one byte fits.
  int maxPayloadWithin(int maxSamples) {
    var lo = 0, hi = FrameCodec.maxPayload;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (samplesForFrameBytes(_frameBytes(mid)) <= maxSamples) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

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
