// Settings screen controls drive AppState (#34): presets, FEC options,
// carrier/bandwidth fields (including invalid input), CSS sliders, OFDM
// dropdowns and equaliser, ARQ retries/timeout and playback volume.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/settings.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

void main() {
  late AppState state;

  setUp(() => state = AppState(audio: MockAudioService()));
  tearDown(() => state.dispose());

  /// Pumps the screen on a surface tall enough to show every card.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder sliderWhere(bool Function(Slider s) test) =>
      find.byWidgetPredicate((w) => w is Slider && test(w));

  Future<void> choose(WidgetTester tester, String current, String next) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(next).last);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextFormField, label), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('presets switch mode and parameters', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('High Speed (OFDM)'));
    await tester.pumpAndSettle();
    expect(state.mode, 1);
    expect(state.numSubcarriers, 2048);
    expect(find.text('FFT Size: 2048'), findsOneWidget);

    await tester.tap(find.text('Defaults'));
    await tester.pumpAndSettle();
    expect(state.mode, 0);
    expect(state.sf, 8);
    expect(state.carrierFreq, 19000.0);
  });

  testWidgets('FEC switch; no coding-rate knob', (tester) async {
    await pumpSettings(tester);
    expect(state.enableRs, isTrue);
    await tester.tap(find.text('Enable Reed-Solomon Correction'));
    await tester.pumpAndSettle();
    expect(state.enableRs, isFalse);
    expect(state.configMap['enable_rs'], isFalse);
    // The FEC is a fixed RS(255,223); a rate selector would do nothing.
    expect(find.textContaining('Rate 1/2'), findsNothing);
    expect(state.configMap.containsKey('coding_rate'), isFalse);
  });

  testWidgets('carrier and bandwidth fields parse, or fall back on garbage',
      (tester) async {
    await pumpSettings(tester);
    await submit(tester, 'Carrier Frequency (Hz)', '18500');
    expect(state.carrierFreq, 18500.0);
    await submit(tester, 'Sweep Bandwidth (Hz)', '3000');
    expect(state.bandwidth, 3000.0);

    await submit(tester, 'Carrier Frequency (Hz)', 'abc');
    expect(state.carrierFreq, 19000.0);
    await submit(tester, 'Sweep Bandwidth (Hz)', '');
    expect(state.bandwidth, 2000.0);
  });

  testWidgets('CSS SF slider sets SF; chirp duration is computed',
      (tester) async {
    await pumpSettings(tester);
    final sf = sliderWhere((s) => s.label?.startsWith('SF ') ?? false);
    // Only the SF slider: the chirp duration follows from SF and bandwidth.
    expect(sliderWhere((s) => s.min == 0.01), findsNothing);
    await tester.drag(sf, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(state.sf, 10);
    expect(find.text('Spreading Factor (SF): 10'), findsOneWidget);
    // SF10 @ 2 kHz: 1024 chips x 22 samples = 510.8 ms, 19.6 bit/s.
    expect(state.symbolDuration, closeTo(1024 * 22 / 44100, 1e-9));
    expect(find.textContaining('510.8 ms per chirp, 10 bits per chirp'),
        findsOneWidget);

    await tester.drag(sf, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(state.sf, 6);
    expect(find.textContaining('6 bits per chirp, 187.9 bit/s raw'),
        findsOneWidget);
  });

  testWidgets('OFDM dropdowns and equaliser', (tester) async {
    state.setMode(1);
    await pumpSettings(tester);

    await choose(tester, 'FFT Size: 256', 'FFT Size: 1024');
    expect(state.numSubcarriers, 1024);
    // CP keeps the 1/4 fraction it had (64 of 256).
    expect(state.cpLength, 256);

    await choose(tester, '1/4 of FFT (256)', '1/16 of FFT (64)');
    expect(state.cpLength, 64);

    await choose(tester, '8 Pilots', '16 Pilots');
    expect(state.numPilots, 16);

    expect(state.equalizer, 0);
    await tester.tap(find.text('MMSE (Noise Regularised)'));
    await tester.pumpAndSettle();
    expect(state.equalizer, 1);
    expect(state.configMap['equalizer'], 1);
  });

  testWidgets('ARQ retries and ACK timeout', (tester) async {
    state.setArqEnabled(true);
    await pumpSettings(tester);

    await tester.tap(find.byKey(const Key('arq_retries')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    expect(state.arqMaxRetries, 5);

    final timeout = find.byKey(const Key('arq_timeout'));
    await tester.drag(timeout, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(state.arqAckTimeoutMs, 2000);
    expect(find.textContaining('ACK Timeout: 2000 ms'), findsOneWidget);
    await tester.drag(timeout, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(state.arqAckTimeoutMs, 200);
  });

  testWidgets('playback volume slider', (tester) async {
    await pumpSettings(tester);
    final volume = sliderWhere((s) => s.label?.endsWith('%') ?? false);
    await tester.drag(volume, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(state.volume, 0.0);
    expect(state.configMap['volume'], 0.0);
  });
}
