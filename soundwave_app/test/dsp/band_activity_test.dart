// Band activity summary for screen readers (#93).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/band_activity.dart';

const binWidth = 44100 / 1024; // 43.07 Hz, the Monitor's FFT
const bins = 513;

/// A -120 dBFS floor with one bin at [db].
Float64List spectrumWithPeak(double hz, double db) {
  final s = Float64List(bins)..fillRange(0, bins, -120);
  s[(hz / binWidth).round()] = db;
  return s;
}

final silence = Float64List(bins)..fillRange(0, bins, -120);

void main() {
  test('describe()', () {
    expect(const BandActivity.quiet().describe(), 'No ultrasonic signal');
    expect(const BandActivity.signal(19012, -15.4).describe(),
        'Ultrasonic signal at 19.0 kHz, -15 dBFS');
  });

  test('a signal starts at once and reports where and how strong', () {
    final d = BandActivityDetector();
    expect(d.update(silence, binWidth, 0.01), isFalse);
    expect(d.state.active, isFalse);
    expect(d.update(spectrumWithPeak(19000, -20), binWidth, 0.01), isTrue);
    expect(d.state.active, isTrue);
    expect(d.state.peakHz, closeTo(19000, binWidth));
    expect(d.state.peakDb, -20);
    // Still on: no further transition, even if the peak moves.
    expect(d.update(spectrumWithPeak(20000, -25), binWidth, 0.01), isFalse);
    expect(d.state.peakHz, closeTo(19000, binWidth));
  });

  test('only energy inside 18-22 kHz counts', () {
    final d = BandActivityDetector();
    expect(d.update(spectrumWithPeak(1000, 0), binWidth, 0.01), isFalse);
    expect(d.update(spectrumWithPeak(17500, -10), binWidth, 0.01), isFalse);
    expect(d.update(spectrumWithPeak(18100, -10), binWidth, 0.01), isTrue);
  });

  test('hysteresis: dips between -70 and -60 dBFS keep it on', () {
    final d = BandActivityDetector();
    d.update(spectrumWithPeak(19000, -50), binWidth, 0.01);
    for (var i = 0; i < 500; i++) {
      expect(d.update(spectrumWithPeak(19000, -65), binWidth, 0.01), isFalse);
    }
    expect(d.state.active, isTrue);
  });

  test('ends only after the hold time below the off threshold', () {
    final d = BandActivityDetector(holdSeconds: 1.0);
    d.update(spectrumWithPeak(19000, -30), binWidth, 0.01);
    // 0.9 s of quiet, then a chirp: no end, and the hold restarts.
    for (var i = 0; i < 90; i++) {
      expect(d.update(silence, binWidth, 0.01), isFalse);
    }
    d.update(spectrumWithPeak(19000, -30), binWidth, 0.01);
    for (var i = 0; i < 99; i++) {
      expect(d.update(silence, binWidth, 0.01), isFalse, reason: 'frame $i');
    }
    expect(d.update(silence, binWidth, 0.02), isTrue);
    expect(d.state, const BandActivity.quiet());
  });

  test('reset, degenerate input and argument checks', () {
    final d = BandActivityDetector();
    d.update(spectrumWithPeak(19000, -30), binWidth, 0.01);
    d.reset();
    expect(d.state.active, isFalse);
    expect(d.update(Float64List(0), binWidth, 0.01), isFalse);
    expect(d.update(silence, 0, 0.01), isFalse);
    expect(d.update(silence, binWidth, double.nan), isFalse);
    expect(
        () => BandActivityDetector(onDb: -70, offDb: -60), throwsArgumentError);
    expect(() => BandActivityDetector(lowHz: 22000, highHz: 18000),
        throwsArgumentError);
  });

  test('value equality', () {
    expect(const BandActivity.signal(1, 2), const BandActivity.signal(1, 2));
    expect(const BandActivity.signal(1, 2).hashCode,
        const BandActivity.signal(1, 2).hashCode);
    expect(const BandActivity.signal(1, 2), isNot(const BandActivity.quiet()));
    expect('${const BandActivity.quiet()}', contains('No ultrasonic signal'));
  });
}
