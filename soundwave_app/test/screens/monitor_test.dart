// Monitor screen: layout, live analysis of mock audio, constellation feed.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/monitor.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/widgets/viz/constellation_widget.dart';
import 'package:soundwave/widgets/viz/spectrum_analyzer_widget.dart';
import 'package:soundwave/widgets/viz/waterfall_widget.dart';
import 'package:soundwave/widgets/viz/waveform_widget.dart';

import '../engine/mock_native.dart';

void main() {
  late MockAudioService audio;
  late AppState state;

  Widget app() => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: MonitorScreen()),
      );

  setUp(() {
    audio = MockAudioService();
    state = AppState(audio: audio);
  });

  tearDown(() => state.dispose());

  testWidgets('narrow layout uses tabs for the four plots', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(audio.isCapturing, isTrue);
    expect(find.text('Spectrum'), findsOneWidget);
    expect(find.byType(SpectrumAnalyzerWidget), findsOneWidget);

    await tester.tap(find.text('Waterfall'));
    await tester.pumpAndSettle();
    expect(find.byType(WaterfallView), findsOneWidget);

    await tester.tap(find.text('Constellation'));
    await tester.pumpAndSettle();
    expect(find.byType(ConstellationDiagram), findsOneWidget);
    // Default mode is CSS: the panel explains what it needs.
    expect(find.textContaining('OFDM mode'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(audio.isCapturing, isFalse);
  });

  testWidgets('wide layout shows all plots at once', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    state.setMode(1);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(SpectrumAnalyzerWidget), findsOneWidget);
    expect(find.byType(WaterfallView), findsOneWidget);
    expect(find.byType(ConstellationDiagram), findsOneWidget);
    expect(find.byType(WaveformWidget), findsOneWidget);
    expect(find.text('Start receiver'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('analyses live audio and reports the ultrasonic peak',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Peak: -- kHz'), findsOneWidget);

    // Bin-centred tone at bin 441 of a 1024-point FFT (18.99 kHz).
    const hz = 441 * 44100 / 1024;
    final x = Float64List.fromList(List.generate(
      4096,
      (i) => 0.25 * math.sin(2 * math.pi * hz * i / 44100),
    ));
    audio.pushMockChunk(x);
    await tester.pump();
    final level = tester.widget<Text>(find.textContaining('Level')).data;
    final peak = tester.widget<Text>(find.textContaining('Peak:')).data;
    expect(level, 'Level -15 dBFS');
    expect(peak, 'Peak: 18.99 kHz');

    // Paused: new audio is not analysed.
    await tester.tap(find.byKey(const ValueKey('monitor-pause')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
