// FFI struct definitions mirroring the C API's sw_config_t and supporting types.
// Used by soundwave_native.dart to call into libsoundwave via dart:ffi.

import 'dart:ffi';

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

  static SwConfig fromMap(Map<String, dynamic> m) {
    final c = calloc<SwConfig>();
    c.sampleRate = (m['sample_rate'] ?? 44100) as int;
    c.modulation = (m['modulation'] ?? 0) as int;
    c.sf = (m['sf'] ?? 8) as int;
    c.numSubcarriers = (m['num_subcarriers'] ?? 256) as int;
    c.cpLength = (m['cp_length'] ?? 64) as int;
    c.numPilots = (m['num_pilots'] ?? 8) as int;
    c.codingRate = ((m['coding_rate'] ?? 0.5) as num).toDouble();
    c.threshold = ((m['threshold'] ?? 3.0) as num).toDouble();
    c.equalizer = (m['equalizer'] ?? 0) as int;
    c.carrierFreq = ((m['carrier_freq'] ?? 19000.0) as num).toDouble();
    c.bandwidth = ((m['bandwidth'] ?? 2000.0) as num).toDouble();
    c.symbolDuration = ((m['symbol_duration'] ?? 0.02) as num).toDouble();
    c.amplitude = ((m['amplitude'] ?? 0.8) as num).toDouble();
    c.ofdmModulation = (m['ofdm_modulation'] ?? 1) as int; // Default 1 = QPSK
    return c;
  }
}

// Opaque handle for audio capture/playback (void* in C)
final class AudioHandle extends Opaque {}

// Error codes (matches sw_error_t)
class SwException implements Exception {
  final int code;
  SwException(this.code);
  @override
  String toString() => 'SwException(code=$code)';
}
