// Real equalized OFDM constellation from the native library (#71):
// FrameCodec -> sw_ofdm_modulate -> noise -> sw_ofdm_equalized_symbols, and
// the RxEngine constellation stream on top of it.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/constellation.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

import '../engine/mock_native.dart' show MockAudioService;

Map<String, dynamic> ofdmConfig({int ofdmModulation = 1}) => {
      'sample_rate': 44100,
      'modulation': 1,
      'sf': 8,
      'num_subcarriers': 256,
      'cp_length': 64,
      'num_pilots': 8,
      'carrier_freq': 19000.0,
      'bandwidth': 2000.0,
      'symbol_duration': 0.02,
      'amplitude': 0.8,
      'ofdm_modulation': ofdmModulation,
      'threshold': 3.0,
      'equalizer': 0,
      'coding_rate': 0.5,
      'enable_rs': true,
      'agc_enabled': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping native constellation tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  test('native library is loadable when required', () {
    if (Platform.environment['SOUNDWAVE_REQUIRE_NATIVE'] == '1') {
      expect(native, isNotNull, reason: 'set SOUNDWAVE_LIB to a built library');
      expect(native!.hasEqualizedSymbols, isTrue);
    }
  });

  Float32List frameSamples(Map<String, dynamic> cfg, String text) {
    final frame = FrameCodec(native!).encode(utf8.encode(text));
    final p = SwConfig.fromMap(cfg);
    try {
      return native!.ofdmModulate(frame, p);
    } finally {
      calloc.free(p);
    }
  }

  Float32List symbols(Map<String, dynamic> cfg, Float32List x, {int? max}) {
    final p = SwConfig.fromMap(cfg);
    try {
      return max == null
          ? native!.ofdmEqualizedSymbols(x, p)
          : native!.ofdmEqualizedSymbols(x, p, maxPoints: max);
    } finally {
      calloc.free(p);
    }
  }

  group('sw_ofdm_equalized_symbols via FFI', () {
    test('QPSK frame: points sit on the QPSK grid', () {
      final cfg = ofdmConfig();
      final iq = symbols(cfg, frameSamples(cfg, 'constellation test 123'));
      expect(iq.length, greaterThan(100));
      expect(iq.length.isEven, isTrue);
      final evm = EvmResult.compute(iq, ConstellationScheme.qpsk)!;
      expect(evm.rms, lessThan(0.2), reason: 'EVM ${evm.percent}%');
    });

    test('BPSK frame: points sit on the real axis', () {
      final cfg = ofdmConfig(ofdmModulation: 0);
      final iq = symbols(cfg, frameSamples(cfg, 'bpsk'));
      final evm = EvmResult.compute(iq, ConstellationScheme.bpsk)!;
      expect(evm.rms, lessThan(0.2), reason: 'EVM ${evm.percent}%');
    });

    test('noise raises the EVM', () {
      final cfg = ofdmConfig();
      final clean = frameSamples(cfg, 'noise test');
      final rnd = Random(91);
      final noisy = Float32List.fromList([
        for (final s in clean) s + (rnd.nextDouble() * 2 - 1) * 0.02,
      ]);
      final evmClean =
          EvmResult.compute(symbols(cfg, clean), ConstellationScheme.qpsk)!;
      final evmNoisy =
          EvmResult.compute(symbols(cfg, noisy), ConstellationScheme.qpsk)!;
      expect(evmNoisy.rms, greaterThan(evmClean.rms));
    });

    test('maxPoints truncates to the first points', () {
      final cfg = ofdmConfig();
      final x = frameSamples(cfg, 'truncate');
      final all = symbols(cfg, x);
      final first = symbols(cfg, x, max: 5);
      expect(first, hasLength(10));
      expect(first, all.sublist(0, 10));
    });

    test('CSS configs are rejected', () {
      final cfg = ofdmConfig()..['modulation'] = 0;
      expect(
        () => symbols(cfg, Float32List(4096)),
        throwsA(isA<SwException>().having((e) => e.code, 'code', -1)),
      );
    });
  }, skip: skip);

  test('RxEngine publishes the constellation of a received frame', () async {
    final cfg = ofdmConfig();
    final audio = MockAudioService();
    final rx = RxEngine(
      native: native,
      audio: audio,
      configMap: cfg,
      useIsolates: false,
    );
    final frames = <ConstellationFrame>[];
    final messages = <String>[];
    final sub = rx.constellation.listen(frames.add);
    final msgSub = rx.startListening().listen((m) => messages.add(m.text));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rnd = Random(71);
    final signal = frameSamples(cfg, 'hello constellation');
    final g = FrameGeometry.fromConfig(cfg);
    final tail = 2 * RxEngine.retryStepSymbols * g.samplesPerSymbol;
    final stream = Float64List(3000 + signal.length + tail);
    for (var i = 0; i < stream.length; i++) {
      stream[i] = (rnd.nextDouble() * 2 - 1) * 0.01;
    }
    for (var i = 0; i < signal.length; i++) {
      stream[3000 + i] += signal[i];
    }
    for (var i = 0; i < stream.length; i += 1024) {
      final end = min(i + 1024, stream.length);
      audio.pushMockChunk(Float64List.sublistView(stream, i, end));
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    rx.stopListening();
    await sub.cancel();
    await msgSub.cancel();

    expect(messages, ['hello constellation']);
    expect(frames, isNotEmpty);
    expect(frames.first.decoded, isTrue);
    expect(frames.first.scheme, ConstellationScheme.qpsk);
    expect(frames.first.evm!.rms, lessThan(0.3));
  }, skip: skip);
}
