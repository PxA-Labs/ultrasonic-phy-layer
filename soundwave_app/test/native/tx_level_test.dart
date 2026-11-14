// Transmit level through the app's real TX path (TxEngine -> FrameCodec ->
// sw_*_modulate via FFI -> AudioService.enqueueForPlayback): every sample
// handed to playback must lie within +-amplitude <= 1, for OFDM (per-frame
// peak normalization) and CSS (constant envelope) alike. Anything above full
// scale would be hard-clipped by the device, splattering energy into the
// audible band.
//
// Runs only when libsoundwave can be loaded (CI builds it first).

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/native/soundwave_native.dart';

import '../engine/mock_native.dart' show MockAudioService;

Map<String, dynamic> _config({
  required int modulation,
  int sf = 8,
  int subcarriers = 256,
  int cp = 64,
  int ofdmModulation = 1,
  double amplitude = 0.8,
}) =>
    {
      'sample_rate': 44100,
      'modulation': modulation,
      'sf': sf,
      'num_subcarriers': subcarriers,
      'cp_length': cp,
      'num_pilots': 8,
      'carrier_freq': 19000.0,
      'bandwidth': 2000.0,
      'symbol_duration': 0.02,
      'amplitude': amplitude,
      'ofdm_modulation': ofdmModulation,
      'threshold': 3.0,
      'equalizer': 0,
      'coding_rate': 0.5,
      'enable_rs': true,
    };

int _alternating(int i) => i.isEven ? 0xAA : 0x55;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping TX level tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  test('native library is loadable when required', () {
    if (Platform.environment['SOUNDWAVE_REQUIRE_NATIVE'] == '1') {
      expect(native, isNotNull, reason: 'set SOUNDWAVE_LIB to a built library');
    }
  });

  // Worst-case and typical payloads (OFDM whitens the data, but the
  // contract must hold for any input).
  const n = FrameCodec.maxPayload;
  final payloads = <String, Uint8List>{
    'zeros': Uint8List(n),
    '0xFF': Uint8List.fromList(List.filled(n, 0xFF)),
    'alternating': Uint8List.fromList(List.generate(n, _alternating)),
    'text': Uint8List.fromList('Ultrasonic hello 123'.codeUnits),
  };

  Future<Float64List> transmit(Map<String, dynamic> c, Uint8List p) async {
    final audio = MockAudioService();
    final tx = TxEngine(
      native: native,
      audio: audio,
      configMap: c,
      useIsolates: false,
      nodeId: 1,
    );
    await tx.transmitPayload(p);
    expect(audio.playbackQueue, isNotNull);
    return audio.playbackQueue!;
  }

  void expectWithinAmplitude(Float64List s, double amplitude, String what) {
    var peak = 0.0;
    var nonFinite = 0;
    for (final v in s) {
      if (!v.isFinite) nonFinite++;
      final a = v.abs();
      if (a > peak) peak = a;
    }
    expect(nonFinite, 0, reason: '$what: non-finite samples');
    // Float32 samples of a float32 amplitude: allow one float32 ulp.
    final limit = amplitude * (1 + 1.2e-7);
    expect(peak, lessThanOrEqualTo(limit), reason: '$what: peak $peak');
    expect(peak, lessThanOrEqualTo(1.0), reason: '$what: peak $peak');
    // The contract is not met by transmitting silence.
    final floor = 0.95 * amplitude;
    expect(peak, greaterThan(floor), reason: '$what: peak $peak');
  }

  group('TxEngine output stays within +-amplitude (real DSP)', () {
    // [N, cp, ofdm_modulation (0 BPSK, 1 QPSK), amplitude]
    const ofdm = [
      [256, 64, 1, 0.8],
      [256, 32, 0, 0.8],
      [512, 64, 1, 0.8],
      [1024, 128, 1, 0.8],
      [2048, 256, 1, 1.0],
      [4096, 512, 0, 0.8],
    ];
    for (final o in ofdm) {
      final amp = o[3].toDouble();
      final name = 'OFDM N=${o[0]} cp=${o[1]} mod=${o[2]} amp=$amp';
      test(name, () async {
        final cfg = _config(
          modulation: 1,
          subcarriers: o[0].toInt(),
          cp: o[1].toInt(),
          ofdmModulation: o[2].toInt(),
          amplitude: amp,
        );
        for (final e in payloads.entries) {
          final s = await transmit(cfg, e.value);
          expectWithinAmplitude(s, amp, '$name ${e.key}');
        }
      }, skip: skip);
    }

    for (var sf = 6; sf <= 10; sf++) {
      final amp = sf.isEven ? 1.0 : 0.5;
      test('CSS SF$sf amp=$amp', () async {
        final cfg = _config(modulation: 0, sf: sf, amplitude: amp);
        for (final key in ['text', 'alternating']) {
          final s = await transmit(cfg, payloads[key]!);
          expectWithinAmplitude(s, amp, 'CSS SF$sf $key');
        }
      }, skip: skip);
    }
  });
}
