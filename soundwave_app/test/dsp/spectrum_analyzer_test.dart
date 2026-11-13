// SpectrumAnalyzer (windowed FFT -> dBFS) and PeakHold (#71, #91).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/fft.dart';
import 'package:soundwave/dsp/spectrum_analyzer.dart';

List<double> tone(double hz, double amp, int n, {double fs = 44100}) =>
    List.generate(n, (i) => amp * math.sin(2 * math.pi * hz * i / fs));

int argMax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

void main() {
  group('SpectrumAnalyzer.analyze', () {
    final a = SpectrumAnalyzer(fftSize: 1024, sampleRate: 44100);

    test('bin geometry', () {
      expect(a.binCount, 513);
      expect(a.binWidthHz, closeTo(43.0664, 1e-4));
      expect(a.frequencyOfBin(512), closeTo(22050, 1e-9));
      expect(a.binForFrequency(19000), 441);
      expect(a.binForFrequency(-5), 0);
      expect(a.binForFrequency(1e6), 512);
      expect(a.hopSize, 512);
      expect(a.secondsPerFrame, closeTo(512 / 44100, 1e-12));
    });

    test('a bin-centred tone reads its amplitude in dBFS', () {
      const bin = 441; // 18.99 kHz
      final spectrum = a.analyze(tone(bin * a.binWidthHz, 0.5, 1024));
      expect(argMax(spectrum), bin);
      expect(spectrum[bin], closeTo(-6.0206, 0.01));
      // Hann: each neighbouring bin holds half the amplitude (-6 dB).
      expect(spectrum[bin - 1], closeTo(-12.0412, 0.01));
      expect(spectrum[bin + 1], closeTo(-12.0412, 0.01));
      // Leakage elsewhere is negligible.
      expect(spectrum[bin - 10], lessThan(-100));
      expect(spectrum[100], lessThan(-120));
    });

    test('an off-bin tone peaks at the nearest bin within Hann scalloping',
        () {
      final spectrum = a.analyze(tone(19000, 1.0, 1024));
      expect(argMax(spectrum), a.binForFrequency(19000));
      // Worst-case Hann scalloping loss is 1.42 dB.
      expect(spectrum[argMax(spectrum)], inInclusiveRange(-1.45, 0.01));
    });

    test('resolves two ultrasonic tones', () {
      final x = tone(18000, 0.3, 1024);
      final y = tone(20500, 0.3, 1024);
      final spectrum = a.analyze(List.generate(1024, (i) => x[i] + y[i]));
      final b1 = a.binForFrequency(18000);
      final b2 = a.binForFrequency(20500);
      final mid = a.binForFrequency(19250);
      expect(spectrum[b1], greaterThan(-14));
      expect(spectrum[b2], greaterThan(-14));
      expect(spectrum[mid], lessThan(-80));
    });

    test('DC is scaled without the one-sided factor of two', () {
      final spectrum = a.analyze(List.filled(1024, 0.25));
      expect(spectrum[0], closeTo(-12.0412, 1e-6));
    });

    test('silence reads the floor', () {
      final spectrum = a.analyze(List.filled(1024, 0.0));
      expect(spectrum.every((v) => v == kSpectrumFloorDb), isTrue);
    });

    test('rejects frames of the wrong length', () {
      expect(() => a.analyze(List.filled(512, 0.0)), throwsArgumentError);
    });
  });

  group('SpectrumAnalyzer.addSamples (streaming)', () {
    final signal = tone(19000, 0.5, 10000);

    test('emits one frame per hop once the first window is full', () {
      final a = SpectrumAnalyzer(fftSize: 1024, maxFramesPerPush: 100);
      expect(a.addSamples(signal.sublist(0, 1023)), isEmpty);
      expect(a.addSamples(signal.sublist(1023, 1024)), hasLength(1));
      expect(a.addSamples(signal.sublist(1024, 1535)), isEmpty);
      expect(a.addSamples(signal.sublist(1535, 1536)), hasLength(1));
      // 4096 samples total: 1 + (4096 - 1024) / 512 frames.
      final b = SpectrumAnalyzer(fftSize: 1024, maxFramesPerPush: 100);
      expect(b.addSamples(signal.sublist(0, 4096)), hasLength(7));
    });

    test('chunking does not change the frames', () {
      final reference = SpectrumAnalyzer(maxFramesPerPush: 100);
      final whole = reference.addSamples(signal.sublist(0, 6000));
      final chunked = SpectrumAnalyzer(maxFramesPerPush: 100);
      final frames = <Float64List>[];
      for (var i = 0; i < 6000; i += 333) {
        final end = math.min(i + 333, 6000);
        frames.addAll(chunked.addSamples(signal.sublist(i, end)));
      }
      expect(frames.length, whole.length);
      for (var f = 0; f < frames.length; f++) {
        for (var k = 0; k < frames[f].length; k++) {
          expect(frames[f][k], closeTo(whole[f][k], 1e-9));
        }
      }
    });

    test('streamed frames equal analyze() of the same window', () {
      final a = SpectrumAnalyzer(maxFramesPerPush: 100);
      final frames = a.addSamples(signal.sublist(0, 2048));
      final direct = SpectrumAnalyzer().analyze(signal.sublist(1024, 2048));
      for (var k = 0; k < direct.length; k++) {
        expect(frames.last[k], closeTo(direct[k], 1e-9));
      }
    });

    test('a backlog keeps only the newest maxFramesPerPush frames', () {
      final all = SpectrumAnalyzer(maxFramesPerPush: 100).addSamples(signal);
      final capped = SpectrumAnalyzer(maxFramesPerPush: 4).addSamples(signal);
      expect(all, hasLength(1 + (10000 - 1024) ~/ 512));
      expect(capped, hasLength(4));
      for (var f = 0; f < 4; f++) {
        final ref = all[all.length - 4 + f];
        for (var k = 0; k < ref.length; k++) {
          expect(capped[f][k], closeTo(ref[k], 1e-9));
        }
      }
    });

    test('reset discards buffered samples', () {
      final a = SpectrumAnalyzer();
      a.addSamples(signal.sublist(0, 1000));
      a.reset();
      expect(a.addSamples(signal.sublist(0, 1000)), isEmpty);
      expect(a.addSamples(signal.sublist(1000, 1024)), hasLength(1));
    });

    test('rejects invalid parameters', () {
      expect(() => SpectrumAnalyzer(fftSize: 1000), throwsArgumentError);
      expect(() => SpectrumAnalyzer(hopSize: 0), throwsArgumentError);
      expect(() => SpectrumAnalyzer(sampleRate: 0), throwsArgumentError);
    });
  });

  group('PeakHold', () {
    test('holds the maximum, then decays toward the live spectrum', () {
      final p = PeakHold(holdSeconds: 0.5, decayDbPerSecond: 10);
      expect(p.peaks, isNull);
      p.update(Float64List.fromList([-20, -50]), 0.1);
      p.update(Float64List.fromList([-60, -40]), 0.1);
      expect(p.peaks, [-20, -40]); // bin 0 held, bin 1 rose
      // Still inside the hold time: no decay.
      p.update(Float64List.fromList([-60, -60]), 0.3);
      expect(p.peaks![0], -20);
      // Past the hold time: falls by 10 dB/s * dt.
      p.update(Float64List.fromList([-60, -60]), 0.2);
      expect(p.peaks![0], closeTo(-22, 1e-9));
      p.update(Float64List.fromList([-60, -60]), 1.0);
      expect(p.peaks![0], closeTo(-32, 1e-9));
      // Never decays below the live value.
      for (var i = 0; i < 20; i++) {
        p.update(Float64List.fromList([-60, -60]), 1.0);
      }
      expect(p.peaks, [-60, -60]);
    });

    test('restarts on a size change and on reset', () {
      final p = PeakHold();
      p.update(Float64List.fromList([-1, -2]), 0.1);
      p.update(Float64List.fromList([-5, -6, -7]), 0.1);
      expect(p.peaks, [-5, -6, -7]);
      p.reset();
      expect(p.peaks, isNull);
    });
  });
}
