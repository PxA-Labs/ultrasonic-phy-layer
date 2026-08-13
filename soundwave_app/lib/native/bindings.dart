// FFI struct definitions mirroring the C API's sw_config_t and supporting types.
// Used by soundwave_native.dart to call into libsoundwave via dart:ffi.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Mirrors native/sw_config_t
final class SwConfig extends Struct {
  @Int32()
  external int sampleRate;

  @Int32()
  external int modulation;

  @Int32()
  external int sf;

  @Int32()
  external int numSubcarriers;

  @Int32()
  external int cpLength;

  @Int32()
  external int numPilots;

  @Float()
  external double codingRate;

  @Float()
  external double threshold;

  @Int32()
  external int equalizer;

  @Float()
  external double carrierFreq;

  @Float()
  external double bandwidth;

  @Float()
  external double symbolDuration;

  @Float()
  external double amplitude;

  @Int32()
  external int ofdmModulation;

  static Pointer<SwConfig> fromMap(Map<String, dynamic> m) {
    final c = calloc<SwConfig>();
    c.ref.sampleRate = (m['sample_rate'] ?? 44100) as int;
    c.ref.modulation = (m['modulation'] ?? 0) as int;
    c.ref.sf = (m['sf'] ?? 8) as int;
    c.ref.numSubcarriers = (m['num_subcarriers'] ?? 256) as int;
    c.ref.cpLength = (m['cp_length'] ?? 64) as int;
    c.ref.numPilots = (m['num_pilots'] ?? 8) as int;
    c.ref.codingRate = ((m['coding_rate'] ?? 0.5) as num).toDouble();
    c.ref.threshold = ((m['threshold'] ?? 3.0) as num).toDouble();
    c.ref.equalizer = (m['equalizer'] ?? 0) as int;
    c.ref.carrierFreq = ((m['carrier_freq'] ?? 19000.0) as num).toDouble();
    c.ref.bandwidth = ((m['bandwidth'] ?? 2000.0) as num).toDouble();
    c.ref.symbolDuration = ((m['symbol_duration'] ?? 0.02) as num).toDouble();
    c.ref.amplitude = ((m['amplitude'] ?? 0.8) as num).toDouble();
    c.ref.ofdmModulation =
        (m['ofdm_modulation'] ?? 1) as int; // Default 1 = QPSK
    return c;
  }
}

// Error codes (matches sw_error_t)
class SwException implements Exception {
  final int code;
  SwException(this.code);

  String get message {
    switch (code) {
      case -1:
        return 'Invalid parameter or NULL pointer';
      case -2:
        return 'Out of memory';
      case -3:
        return 'RS decode failure (too many errors)';
      case -4:
        return 'Frame synchronisation/CFO estimate failed';
      case -5:
        return 'Real-time audio device I/O error';
      case -6:
        return 'Feature not implemented';
      case -7:
        return 'Output buffer too small / overflow';
      default:
        return 'Unknown native code: $code';
    }
  }

  @override
  String toString() => 'SwException(code=$code, message="$message")';
}
