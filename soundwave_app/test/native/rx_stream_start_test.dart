// The first frame after listening starts must decode (real native DSP).
//
// Regression test for frames arriving shortly after capture start: the RX
// engine is started, then the microphone delivers [lead] of silence or
// background noise followed by one frame, in 10 ms chunks like the native
// capture poller. Covers the leads seen in practice (0/20/45/100 ms) and a
// sweep of sample offsets around the detection-window edge, with AGC on and
// off. Skipped when libsoundwave cannot be loaded.

import 'dart:convert';
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

Map<String, dynamic> config({required int modulation, bool agc = true}) => {
      'sample_rate': 44100,
      'modulation': modulation,
      'sf': 7,
      'num_subcarriers': 256,
      'cp_length': 64,
      'num_pilots': 8,
      'carrier_freq': 19000.0,
      'bandwidth': 2000.0,
      'symbol_duration': 0.02,
      'amplitude': 0.8,
      'ofdm_modulation': 1,
      'threshold': 3.0,
      'equalizer': 0,
      'coding_rate': 0.5,
      'enable_rs': true,
      'agc_enabled': agc,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping RX stream-start tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

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

  /// Starts a fresh RxEngine, feeds [lead] samples of silence / noise, one
  /// frame carrying [text] and trailing noise, and returns what it decoded.
  Future<List<String>> receiveAfter(
    Map<String, dynamic> cfg,
    int lead, {
    required bool noise,
    String text = 'first frame',
  }) async {
    final audio = MockAudioService();
    final rx = RxEngine(
        native: native, audio: audio, configMap: cfg, useIsolates: false);
    final texts = <String>[];
    final sub = rx.startListening().listen((m) => texts.add(m.text));
    // Capture is attached asynchronously, as with a real microphone.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final g = FrameGeometry.fromConfig(cfg);
    final signal = modulate(
        cfg, FrameCodec(native!).encode(Uint8List.fromList(utf8.encode(text))));
    final tail = g.searchWindowSamples + g.maxFrameSamples;
    final rnd = Random(lead * 7 + (noise ? 1 : 0));
    final x = Float64List(lead + signal.length + tail);
    for (var i = 0; i < x.length; i++) {
      // The lead is pure silence or noise; the frame and tail always noisy.
      if (noise || i >= lead) x[i] = (rnd.nextDouble() * 2 - 1) * 0.01;
    }
    for (var i = 0; i < signal.length; i++) {
      x[lead + i] += signal[i];
    }
    for (var i = 0; i < x.length; i += 441) {
      audio.pushMockChunk(
          Float64List.sublistView(x, i, min(i + 441, x.length)));
      if (i % (441 * 50) == 0) await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 100 && texts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    rx.stopListening();
    await sub.cancel();
    return texts;
  }

  int ms(int v) => v * 44100 ~/ 1000;

  for (final modulation in [1, 0]) {
    final name = modulation == 1 ? 'OFDM' : 'CSS SF7';
    group('$name: first frame after listening starts', () {
      for (final agc in [true, false]) {
        for (final noise in [true, false]) {
          final kind =
              '${noise ? 'noise' : 'silence'}, AGC ${agc ? 'on' : 'off'}';
          test('decodes after 0/20/45/100 ms of $kind', () async {
            final cfg = config(modulation: modulation, agc: agc);
            final failed = <int>[];
            for (final lead in [0, 20, 45, 100]) {
              final texts = await receiveAfter(cfg, ms(lead), noise: noise);
              if (texts.length != 1 || texts.single != 'first frame') {
                failed.add(lead);
              }
            }
            expect(failed, isEmpty, reason: 'leads (ms) that failed: $failed');
          }, timeout: const Timeout(Duration(minutes: 2)));
        }
      }

      test('decodes wherever the preamble falls relative to the search window',
          () async {
        final cfg = config(modulation: modulation);
        final g = FrameGeometry.fromConfig(cfg);
        final w = g.searchWindowSamples;
        final p = g.preambleSamples;
        final s = g.samplesPerSymbol;
        // Offsets around the edges where a preamble starts to straddle the
        // first window (w - p) and leaves it (w).
        final leads = <int>{w - p ~/ 2, w - s, w - 1};
        for (var k = -2; k <= 6; k++) {
          leads.add(w - p + k * s ~/ 2);
        }
        final failed = <int>[];
        for (final lead in leads.toList()..sort()) {
          final texts = await receiveAfter(cfg, lead, noise: true);
          if (texts.length != 1) failed.add(lead);
        }
        expect(failed, isEmpty,
            reason: 'window $w, preamble $p, symbol $s; failing leads $failed');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }, skip: skip);
  }
}
