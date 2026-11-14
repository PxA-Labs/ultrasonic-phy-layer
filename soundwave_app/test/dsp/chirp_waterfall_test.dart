// #91 acceptance: "chirp signals produce distinctive diagonal streaks in the
// waterfall". A linear chirp is fed through the same analysis chain as the
// Monitor (inline and on the worker isolate) and into the waterfall buffer;
// the ridge (peak bin per row) must be a straight line with the chirp's
// sweep rate. The real CSS waveform from libsoundwave is checked in
// test/native/css_waterfall_test.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/spectrum_pipeline.dart';
import 'package:soundwave/dsp/waterfall_buffer.dart';

import 'ridge_fit.dart';

const fs = 44100.0;
const config = SpectrumConfig(fftSize: 1024, sampleRate: fs);

/// Linear chirp from [f0] to [f1] over [seconds] (continuous phase).
Float64List linearChirp(double f0, double f1, double seconds,
    {double amp = 0.3}) {
  final n = (seconds * fs).round();
  final k = (f1 - f0) / seconds;
  return Float64List.fromList(List.generate(n, (i) {
    final t = i / fs;
    return amp * math.cos(2 * math.pi * (f0 * t + 0.5 * k * t * t));
  }));
}

/// Fits the ridge frequency (Hz) against row time (s) over [rows], oldest
/// first, restricted to [loHz, hiHz].
LineFit ridgeFit(List<List<double>> rows, double secondsPerRow,
    {double loHz = 17000, double hiHz = 22000}) {
  final lo = (loHz / config.binWidthHz).floor();
  final hi = (hiHz / config.binWidthHz).ceil();
  final t = <double>[], f = <double>[];
  for (var r = 0; r < rows.length; r++) {
    t.add(r * secondsPerRow);
    f.add(ridgeBin(rows[r], lo, hi) * config.binWidthHz);
  }
  return fitLine(t, f);
}

void main() {
  // 18 -> 21 kHz in 0.6 s: 5 kHz/s, i.e. ~1.4 bins per 512-sample hop.
  const f0 = 18000.0, f1 = 21000.0, seconds = 0.6;
  const rate = (f1 - f0) / seconds;

  List<Float64List> inlineSpectra(Float64List x) {
    final p = InlineSpectrumPipeline(const SpectrumConfig(
        fftSize: 1024, sampleRate: fs, maxFramesPerPush: 1 << 20));
    final frames = <Float64List>[];
    p.batches.listen((b) => frames.addAll(b.frames));
    p.add(x);
    p.dispose();
    return frames;
  }

  test('an up-chirp is a rising straight ridge at the sweep rate', () {
    final frames = inlineSpectra(linearChirp(f0, f1, seconds));
    expect(frames.length, greaterThan(45));
    final fit = ridgeFit(frames, config.secondsPerFrame);
    expect(fit.slope, closeTo(rate, rate * 0.03));
    expect(fit.r2, greaterThan(0.995));
    // Never more than ~1.5 bins off the line.
    expect(fit.maxResidual, lessThan(1.5 * config.binWidthHz));
    // Rows are ordered in time: the ridge climbs monotonically.
    final lo = (17000 / config.binWidthHz).floor();
    final hi = (22000 / config.binWidthHz).ceil();
    final bins = [for (final f in frames) ridgeBin(f, lo, hi)];
    for (var i = 1; i < bins.length; i++) {
      expect(bins[i], greaterThanOrEqualTo(bins[i - 1]), reason: 'row $i');
    }
  });

  test('a down-chirp is a falling ridge; a tone is a vertical line', () {
    final down = ridgeFit(
        inlineSpectra(linearChirp(f1, f0, seconds)), config.secondsPerFrame);
    expect(down.slope, closeTo(-rate, rate * 0.03));
    expect(down.r2, greaterThan(0.995));

    final tone = ridgeFit(inlineSpectra(linearChirp(19000, 19000, seconds)),
        config.secondsPerFrame);
    expect(tone.slope.abs(), lessThan(1.0)); // Hz/s: no streak at all
    expect(tone.maxResidual, lessThan(1e-6));
  });

  test('the waterfall buffer holds the streak as a diagonal', () async {
    // The Monitor's path: worker isolate -> every 2nd frame -> buffer.
    final p = IsolateSpectrumPipeline(const SpectrumConfig(
        fftSize: 1024, sampleRate: fs, maxFramesPerPush: 1 << 20));
    final next = p.batches.first;
    p.add(linearChirp(f0, f1, seconds));
    final frames = (await next.timeout(const Duration(seconds: 20))).frames;
    await p.dispose();

    const decimation = 2;
    final buffer = WaterfallBuffer(capacity: 256, binCount: config.binCount);
    for (var i = 0; i < frames.length; i += decimation) {
      buffer.push(frames[i]);
    }
    // Age 0 is the newest row; read oldest first, as the waterfall draws.
    final rows = [
      for (var age = buffer.length - 1; age >= 0; age--)
        [for (var k = 0; k < config.binCount; k++) buffer.valueAt(age, k)],
    ];
    final fit = ridgeFit(rows, config.secondsPerFrame * decimation);
    expect(fit.slope, closeTo(rate, rate * 0.03));
    expect(fit.r2, greaterThan(0.995));
    // Its ends sit at the chirp's start and end frequencies (one window of
    // sweep is averaged in, so allow ~6 bins at the edges).
    expect(fit.intercept, closeTo(f0, 6 * config.binWidthHz));
  });
}
