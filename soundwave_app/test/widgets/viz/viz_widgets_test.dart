// Widget tests: the visualizers render without exceptions in light and dark
// themes, with and without data, and their controls work (#71, #91).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/constellation.dart';
import 'package:soundwave/dsp/spectrum_analyzer.dart';
import 'package:soundwave/widgets/viz/colormap.dart';
import 'package:soundwave/widgets/viz/constellation_widget.dart';
import 'package:soundwave/widgets/viz/spectrum_analyzer_widget.dart';
import 'package:soundwave/widgets/viz/waterfall_widget.dart';
import 'package:soundwave/widgets/viz/waveform_widget.dart';

Widget host(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: child),
    ),
  );
}

Float64List toneSpectrum(SpectrumAnalyzer a, double hz) {
  final x = List.generate(
    a.fftSize,
    (i) => 0.5 * math.sin(2 * math.pi * hz * i / a.sampleRate),
  );
  return a.analyze(x);
}

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      testWidgets('SpectrumAnalyzerWidget renders empty and with data',
          (tester) async {
        final a = SpectrumAnalyzer();
        final c = SpectrumController(binWidthHz: a.binWidthHz);
        await tester.pumpWidget(
          host(SpectrumAnalyzerWidget(controller: c), brightness: brightness),
        );
        expect(find.byType(SpectrumAnalyzerWidget), findsOneWidget);
        c.update(toneSpectrum(a, 19000), a.secondsPerFrame);
        await tester.pump();
        expect(c.peakBin(18000, 22000), a.binForFrequency(19000));
        // Zoomed range also paints.
        await tester.pumpWidget(host(
          SpectrumAnalyzerWidget(
            controller: c,
            minFrequencyHz: 17000,
            maxFrequencyHz: 23000,
          ),
          brightness: brightness,
        ));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('WaterfallView renders and pause toggles', (tester) async {
        final a = SpectrumAnalyzer();
        final c = WaterfallController(
          rows: 64,
          binCount: a.binCount,
          binWidthHz: a.binWidthHz,
          secondsPerRow: a.secondsPerFrame,
        );
        await tester.pumpWidget(
          host(WaterfallView(controller: c), brightness: brightness),
        );
        expect(find.byIcon(Icons.pause), findsOneWidget);

        for (var i = 0; i < 10; i++) {
          c.addRow(toneSpectrum(a, 18500 + 100.0 * i));
        }
        await tester.pump();
        expect(c.buffer.length, 10);

        await tester.tap(find.byKey(const ValueKey('waterfall-pause')));
        await tester.pump();
        expect(c.paused, isTrue);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        c.addRow(toneSpectrum(a, 20000));
        expect(c.buffer.length, 10, reason: 'paused: rows ignored');

        await tester.tap(find.byKey(const ValueKey('waterfall-pause')));
        await tester.pump();
        expect(c.paused, isFalse);
        expect(find.byIcon(Icons.pause), findsOneWidget);

        // Touch readout: dragging across the plot paints the crosshair.
        final plot = tester.getCenter(find.byType(WaterfallPlot));
        final gesture = await tester.startGesture(plot);
        await gesture.moveBy(const Offset(30, 10));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    });
  }

  testWidgets('WaterfallView colour map and range selectors', (tester) async {
    final c = WaterfallController(
      rows: 16,
      binCount: 513,
      binWidthHz: 44100 / 1024,
      secondsPerRow: 0.02,
    );
    await tester.pumpWidget(host(WaterfallView(controller: c)));
    await tester.tap(find.byKey(const ValueKey('waterfall-colormap')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thermal').last);
    await tester.pumpAndSettle();
    expect(c.colormap, WaterfallColormap.thermal);

    await tester.tap(find.byKey(const ValueKey('waterfall-range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full band').last);
    await tester.pumpAndSettle();
    final plot = tester.widget<WaterfallPlot>(find.byType(WaterfallPlot));
    expect(plot.minFrequencyHz, 0);
    expect(plot.maxFrequencyHz, closeTo(22050, 1e-9));

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  group('ConstellationDiagram', () {
    testWidgets('renders empty with a placeholder readout', (tester) async {
      final c = ConstellationController();
      await tester.pumpWidget(host(ConstellationDiagram(controller: c)));
      expect(find.text('QPSK - EVM --'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows points and EVM of the newest frame', (tester) async {
      final c = ConstellationController();
      await tester.pumpWidget(
        host(ConstellationDiagram(controller: c), brightness: Brightness.light),
      );
      const q = 0.70710678;
      c.addFrame(ConstellationFrame(
        iq: Float32List.fromList([q + 0.1, q, -q, q, -q, -q, q, -q]),
        scheme: ConstellationScheme.qpsk,
        decoded: true,
      ));
      await tester.pump();
      // One of four points off by 0.1: EVM = sqrt(0.01 / 4) = 5 %.
      expect(find.textContaining('QPSK - EVM 5.0%'), findsOneWidget);
      expect(find.textContaining('4 pts - CRC ok'), findsOneWidget);

      c.addFrame(ConstellationFrame(
        iq: Float32List.fromList([1, 0, -0.5, 0.2]),
        scheme: ConstellationScheme.bpsk,
        decoded: false,
      ));
      await tester.pump();
      expect(find.textContaining('BPSK - EVM'), findsOneWidget);
      expect(find.textContaining('CRC failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('WaveformWidget renders samples', (tester) async {
    final c = WaveformController(windowSize: 64);
    await tester.pumpWidget(host(WaveformWidget(controller: c)));
    c.addSamples(List.generate(100, (i) => math.sin(i / 3)));
    await tester.pump();
    expect(c.levelDbfs, lessThan(0));
    expect(c.samples[63], closeTo(math.sin(99 / 3), 1e-6));
    c.addSamples([0.5]);
    expect(c.samples[63], 0.5);
    expect(c.samples[62], closeTo(math.sin(99 / 3), 1e-6));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
