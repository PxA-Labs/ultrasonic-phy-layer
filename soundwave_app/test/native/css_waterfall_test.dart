// #91 acceptance on the real waveform: a CSS frame from libsoundwave, run
// through the Monitor's spectrum analysis, shows its preamble up-chirps as
// rising streaks and its sync down-chirps as falling ones, at the sweep
// rate B/T of docs/MATHEMATICAL_MODEL.md §2.1.2. Skipped when the library
// cannot be loaded (required in CI via SOUNDWAVE_REQUIRE_NATIVE).

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/spectrum_pipeline.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

import '../dsp/ridge_fit.dart';

const fs = 44100;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping CSS waterfall test: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  test('native library is loadable when required', () {
    if (Platform.environment['SOUNDWAVE_REQUIRE_NATIVE'] == '1') {
      expect(native, isNotNull, reason: 'set SOUNDWAVE_LIB to a built library');
    }
  });

  test('CSS preamble up-chirps and sync down-chirps are diagonal streaks', () {
    const sf = 8, bandwidth = 2000.0, carrier = 19000.0;
    final cfg = {
      'sample_rate': fs,
      'modulation': 0,
      'sf': sf,
      'carrier_freq': carrier,
      'bandwidth': bandwidth,
      'amplitude': 0.8,
      'threshold': 3.0,
      'enable_rs': true,
      'agc_enabled': false,
    };
    final p = SwConfig.fromMap(cfg);
    final Float32List wave;
    try {
      wave = native!.cssModulate(Uint8List.fromList([0x5A, 0xC3]), p);
    } finally {
      calloc.free(p);
    }

    // §2.1.1: D = round(fs / B_cfg), B = fs / D, N = M * D samples/symbol.
    const m = 1 << sf;
    final d = (fs / bandwidth).round();
    final b = fs / d;
    final n = m * d;
    final sweepRate = b / (n / fs); // B / T in Hz/s
    expect(wave.length, greaterThanOrEqualTo(10 * n));

    const config = SpectrumConfig(
        fftSize: 1024, sampleRate: 44100.0, maxFramesPerPush: 1 << 20);
    final pipeline = InlineSpectrumPipeline(config);
    final frames = <Float64List>[];
    pipeline.batches.listen((batch) => frames.addAll(batch.frames));
    pipeline.add(Float64List.fromList([for (final s in wave) s.toDouble()]));
    pipeline.dispose();

    final lo = ((carrier - b / 2) / config.binWidthHz).floor() - 2;
    final hi = ((carrier + b / 2) / config.binWidthHz).ceil() + 2;

    /// Ridge of every analysis window lying wholly inside one of [symbols],
    /// as (time within the symbol, frequency); windows that straddle a
    /// symbol boundary (where the base chirp wraps) are excluded.
    LineFit streak(Iterable<int> symbols) {
      final t = <double>[], f = <double>[];
      for (var j = 0; j < frames.length; j++) {
        final start = j * config.hopSize; // frame j covers [start, start+fft)
        final sym = start ~/ n;
        if (!symbols.contains(sym)) continue;
        if (start + config.fftSize > (sym + 1) * n) continue;
        final centre = start + config.fftSize / 2 - sym * n;
        t.add(centre / fs);
        f.add(ridgeBin(frames[j], lo, hi) * config.binWidthHz);
      }
      expect(t.length, greaterThan(symbols.length * 6));
      return fitLine(t, f);
    }

    // §2.1.3: 8 base up-chirps, then 2 down-chirps.
    final up = streak(List.generate(8, (i) => i));
    expect(up.slope, closeTo(sweepRate, sweepRate * 0.05));
    expect(up.r2, greaterThan(0.99));
    // It starts near f_c - B/2 (a window of sweep is averaged in).
    expect(up.intercept, closeTo(carrier - b / 2, 3 * config.binWidthHz));

    final down = streak(const [8, 9]);
    expect(down.slope, closeTo(-sweepRate, sweepRate * 0.05));
    expect(down.r2, greaterThan(0.99));
    expect(down.intercept, closeTo(carrier + b / 2, 3 * config.binWidthHz));
  }, skip: skip);
}
