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

  @Int32()
  external int threshold;

  @Int32()
  external int equalizer;

  static SwConfig fromMap(Map<String, dynamic> m) {
    final c = calloc<SwConfig>();
    c.sampleRate = (m['sample_rate'] ?? 44100) as int;
    c.modulation = (m['modulation'] ?? 0) as int;
    c.sf = (m['sf'] ?? 8) as int;
    c.numSubcarriers = (m['num_subcarriers'] ?? 256) as int;
    c.cpLength = (m['cp_length'] ?? 64) as int;
    c.numPilots = (m['num_pilots'] ?? 8) as int;
    c.codingRate = (m['coding_rate'] ?? 0.5) as double;
    c.threshold = (m['threshold'] ?? 3) as int;
    c.equalizer = (m['equalizer'] ?? 0) as int;
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
