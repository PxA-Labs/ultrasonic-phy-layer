// End-to-end TX -> audio -> RX tests against the real native DSP library.
//
// These run only when libsoundwave can be loaded (set SOUNDWAVE_LIB to pin a
// build; CI builds native/ first). They exercise exactly the path the app
// uses: FrameCodec framing, the FFI modulate/demodulate wrappers, frame
// detection, and the RxEngine buffering state machine.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

import '../engine/mock_native.dart' show MockAudioService;

Map<String, dynamic> baseConfig({
  int modulation = 1,
  int subcarriers = 256,
  int cp = 64,
  int ofdmModulation = 1,
}) =>
    {
      'sample_rate': 44100,
      'modulation': modulation,
      'sf': 8,
      'num_subcarriers': subcarriers,
      'cp_length': cp,
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
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping native loopback tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  // CI sets SOUNDWAVE_REQUIRE_NATIVE=1 so a broken library build fails the
  // job instead of silently skipping every real-DSP test.
  test('native library is loadable when required', () {
    if (Platform.environment['SOUNDWAVE_REQUIRE_NATIVE'] == '1') {
      expect(native, isNotNull, reason: 'set SOUNDWAVE_LIB to a built library');
    }
  });

  Float32List modulate(Map<String, dynamic> cfg, Uint8List frame) {
    final p = SwConfig.fromMap(cfg);
    try {
      return cfg['modulation'] == 1
          ? native!.ofdmModulate(frame, p)
          : native!.cssModulate(frame, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Embeds [signal] in uniform noise of amplitude [noise] with [lead]
  /// samples before and [tail] after.
  Float32List inNoise(
      Float32List signal, double noise, int lead, int tail, Random rnd) {
    final x = Float32List(lead + signal.length + tail);
    for (var i = 0; i < x.length; i++) {
      x[i] = (rnd.nextDouble() * 2 - 1) * noise;
    }
    for (var i = 0; i < signal.length; i++) {
      x[lead + i] += signal[i];
    }
    return x;
  }

  group('native geometry', () {
    test('FrameGeometry matches modulator output length exactly', () {
      final codec = FrameCodec(native!);
      final configs = [
        baseConfig(modulation: 0),
        baseConfig(),
        baseConfig(ofdmModulation: 0),
        baseConfig(subcarriers: 512, cp: 64),
        baseConfig(subcarriers: 1024, cp: 128),
      ];
      for (final cfg in configs) {
        for (final len in [1, 27, 100, FrameCodec.maxPayload]) {
          final frame = codec.encode(Uint8List(len));
          expect(modulate(cfg, frame).length,
              FrameGeometry.fromConfig(cfg).samplesForFrameBytes(frame.length),
              reason: 'cfg=$cfg payload=$len');
        }
      }
    });
  }, skip: skip);

  group('native codec loopback (modulate -> noise -> detect -> demod)', () {
    final cases = <String, Map<String, dynamic>>{
      'OFDM QPSK N=256': baseConfig(),
      'OFDM BPSK N=256': baseConfig(ofdmModulation: 0),
      'OFDM QPSK N=512': baseConfig(subcarriers: 512, cp: 64),
      'OFDM QPSK N=1024': baseConfig(subcarriers: 1024, cp: 128),
      'CSS SF8': baseConfig(modulation: 0),
    };
    cases.forEach((name, cfg) {
      test(name, () {
        final codec = FrameCodec(native!);
        final rnd = Random(name.hashCode);
        const text = 'Ultrasonic hello 123';
        final frame = codec.encode(Uint8List.fromList(utf8.encode(text)));
        for (final noise in [0.005, 0.05]) {
          final x = inNoise(modulate(cfg, frame), noise, 1234, 4000, rnd);
          final p = SwConfig.fromMap(cfg);
          try {
            final start = native.detectFrame(x, p)['frame_start'] as int;
            expect((start - 1234).abs(), lessThan(8),
                reason: 'detected $start, true 1234, noise $noise');
            final aligned = Float32List.sublistView(x, start);
            final bytes = cfg['modulation'] == 1
                ? native.ofdmDemodulate(aligned, p)
                : native.cssDemodulate(aligned, p);
            final decoded = codec.decode(bytes);
            expect(decoded, isNotNull, reason: 'noise $noise');
            expect(utf8.decode(decoded!.payload), text);
            expect(decoded.frameLength, frame.length);
          } finally {
            calloc.free(p);
          }
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    });
  }, skip: skip);

  group('native RxEngine end-to-end', () {
    Future<List<DecodedMessage>> receive(
        Map<String, dynamic> cfg, List<String> texts) async {
      final codec = FrameCodec(native!);
      final rnd = Random(7);
      final audio = MockAudioService();
      final rx = RxEngine(
          native: native, audio: audio, configMap: cfg, useIsolates: false);
      final got = <DecodedMessage>[];
      final sub = rx.startListening().listen(got.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Silence/noise, frames separated by gaps, trailing noise.
      final parts = <Float32List>[];
      for (final t in texts) {
        final frame = codec.encode(Uint8List.fromList(utf8.encode(t)));
        parts.add(inNoise(modulate(cfg, frame), 0.01, 3000, 1500, rnd));
      }
      // A live microphone keeps delivering audio after the frame; RX retries
      // a decode every RxEngine.retryStepSymbols symbols, so feed at least
      // that much trailing noise.
      final g = FrameGeometry.fromConfig(cfg);
      final trailing = 2 * RxEngine.retryStepSymbols * g.samplesPerSymbol;
      parts.add(inNoise(Float32List(0), 0.01, 0, trailing, rnd));
      final stream = Float64List.fromList([for (final p in parts) ...p]);

      const chunk = 1024;
      for (var i = 0; i < stream.length; i += chunk) {
        audio.pushMockChunk(
            Float64List.sublistView(stream, i, min(i + chunk, stream.length)));
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      rx.stopListening();
      await sub.cancel();
      return got;
    }

    test('OFDM: receives two back-to-back messages from chunked audio',
        () async {
      final got = await receive(baseConfig(), ['first message', 'second!']);
      expect(got.map((m) => m.text).toList(), ['first message', 'second!']);
    });

    test('OFDM: BPSK, N=512', () async {
      final got = await receive(
          baseConfig(subcarriers: 512, cp: 64, ofdmModulation: 0), ['bpsk']);
      expect(got.map((m) => m.text).toList(), ['bpsk']);
    });

    test('CSS: receives a short message', () async {
      final got = await receive(baseConfig(modulation: 0), ['Hi']);
      expect(got.map((m) => m.text).toList(), ['Hi']);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: skip);
}
