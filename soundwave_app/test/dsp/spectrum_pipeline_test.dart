// Off-UI-thread spectrum analysis (#91): the worker isolate must produce
// exactly what the inline analyzer does, shed load instead of queueing it,
// honour resets and shut down cleanly. Real isolates, so plain async tests.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/spectrum_pipeline.dart';

const config = SpectrumConfig(fftSize: 1024, sampleRate: 44100);

Float64List tone(double hz, int n, {double amp = 0.3, int offset = 0}) =>
    Float64List.fromList(List.generate(
        n, (i) => amp * math.sin(2 * math.pi * hz * (i + offset) / 44100)));

int peakBin(Float64List spectrum) {
  var best = 0;
  for (var k = 1; k < spectrum.length; k++) {
    if (spectrum[k] > spectrum[best]) best = k;
  }
  return best;
}

/// Collects batches until [frames] spectra have arrived (or times out).
Future<List<Float64List>> collect(SpectrumPipeline p, int frames) async {
  final out = <Float64List>[];
  final done = Completer<void>();
  final sub = p.batches.listen((b) {
    out.addAll(b.frames);
    if (out.length >= frames && !done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(seconds: 20));
  await sub.cancel();
  return out;
}

void main() {
  test('isolate spectra are identical to the inline analyzer\'s', () async {
    final rnd = math.Random(91);
    final chunks = [
      for (var c = 0; c < 6; c++)
        Float64List.fromList(List.generate(
          2048,
          (i) =>
              0.2 * math.sin(2 * math.pi * 19000 * (c * 2048 + i) / 44100) +
              0.05 * (rnd.nextDouble() * 2 - 1),
        )),
    ];

    final inline = InlineSpectrumPipeline(config);
    final expected = <Float64List>[];
    inline.batches.listen((b) => expected.addAll(b.frames));
    for (final c in chunks) {
      inline.add(c);
    }
    await inline.dispose();
    expect(expected, isNotEmpty);

    final iso = IsolateSpectrumPipeline(config);
    final got = <Float64List>[];
    for (final c in chunks) {
      // One chunk per round trip, so batching matches the inline run.
      final next = iso.batches.first;
      iso.add(c);
      got.addAll((await next.timeout(const Duration(seconds: 20))).frames);
    }
    await iso.dispose();

    expect(got.length, expected.length);
    for (var f = 0; f < got.length; f++) {
      expect(got[f], orderedEquals(expected[f]), reason: 'frame $f');
    }
    expect(peakBin(got.last), 441); // 19 kHz
  });

  test('a busy worker sheds load: bounded backlog, newest audio kept',
      () async {
    final iso = IsolateSpectrumPipeline(config);
    final batches = <SpectrumBatch>[];
    final sub = iso.batches.listen(batches.add);
    // Five seconds of audio at once, before the worker has even started:
    // old audio is 1 kHz, the newest is 19 kHz.
    for (var c = 0; c < 50; c++) {
      iso.add(tone(1000, 4096, offset: c * 4096));
    }
    iso.add(tone(19000, 4096));
    expect(iso.droppedSamples, greaterThan(40 * 4096));

    for (var i = 0; i < 400 && batches.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sub.cancel();
    expect(batches, isNotEmpty);
    final first = batches.first;
    expect(first.frames.length, lessThanOrEqualTo(config.maxFramesPerPush));
    // The display jumps to the present: the newest spectrum is the 19 kHz
    // tone, not stale 1 kHz audio.
    expect(peakBin(first.frames.last), 441);
    await iso.dispose();
  });

  test('reset discards audio added before it', () async {
    final iso = IsolateSpectrumPipeline(config);
    // Wait until the worker is up so both pushes really reach it.
    final warm = iso.batches.first;
    iso.add(tone(5000, 2048));
    await warm.timeout(const Duration(seconds: 20));

    final frames = <Float64List>[];
    final sub = iso.batches.listen((b) => frames.addAll(b.frames));
    iso.add(tone(5000, 8192));
    iso.reset();
    iso.add(tone(19000, 8192));
    for (var i = 0; i < 400 && frames.length < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sub.cancel();
    expect(frames, isNotEmpty);
    for (final f in frames) {
      expect(peakBin(f), 441, reason: 'pre-reset 5 kHz audio leaked through');
    }
    await iso.dispose();
  });

  test('dispose right after creation is clean and stops output', () async {
    final iso = IsolateSpectrumPipeline(config);
    var got = 0;
    iso.batches.listen((b) => got += b.frames.length, onDone: () {});
    iso.add(tone(19000, 4096));
    await iso.dispose();
    iso.add(tone(19000, 4096)); // ignored after dispose
    iso.reset(); // no-op after dispose
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(got, 0);
  });

  test('inline pipeline delivers synchronously and reports skipped frames', () {
    final inline = InlineSpectrumPipeline(config);
    final batches = <SpectrumBatch>[];
    inline.batches.listen(batches.add);
    inline.add(tone(19000, 4096));
    expect(batches, hasLength(1)); // before add() returned
    expect(batches.single.frames, hasLength(7)); // (4096-1024)/512 + 1
    expect(batches.single.skipped, 0);

    inline.add(tone(19000, 44100)); // one second in one push
    expect(batches.last.frames, hasLength(config.maxFramesPerPush));
    expect(batches.last.skipped, greaterThan(70));
    expect(inline.skippedFrames, batches.last.skipped);

    inline.reset();
    inline.add(tone(19000, 512)); // not a full window after reset
    expect(batches, hasLength(2));
    inline.dispose();
  });

  test('preferred() uses the worker isolate on native platforms', () async {
    final p = SpectrumPipeline.preferred(config);
    expect(p, isA<IsolateSpectrumPipeline>());
    await p.dispose();
  });

  test('SpectrumConfig derives the analyzer geometry', () {
    expect(config.hopSize, 512);
    expect(config.binCount, 513);
    expect(config.binWidthHz, closeTo(43.07, 0.01));
    expect(config.secondsPerFrame, closeTo(512 / 44100, 1e-12));
    final a = config.createAnalyzer();
    expect(a.fftSize, 1024);
    expect(a.binCount, config.binCount);
  });
}
