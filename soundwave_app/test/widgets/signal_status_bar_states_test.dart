// SignalStatusBar for every link state and metric combination: status label,
// subtitle and colour per state, SNR colour bands, the frame error / decoded
// badges, throughput and AGC readouts, and reduce-motion (#34).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/theme/soundwave_theme.dart';
import 'package:soundwave/widgets/signal_status_bar.dart';

import '../engine/mock_native.dart';

/// AppState whose metrics are set directly by the test.
class FixedMetricsState extends AppState {
  SignalMetrics fixed;
  FixedMetricsState(this.fixed) : super(audio: MockAudioService());

  @override
  SignalMetrics get metrics => fixed;
}

Future<FixedMetricsState> pumpBar(WidgetTester tester, SignalMetrics m,
    {bool reduceMotion = false, ThemeData? theme}) async {
  final state = FixedMetricsState(m);
  addTearDown(state.dispose);
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: theme ?? SoundwaveTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
          ),
          child: const Scaffold(body: SignalStatusBar()),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  return state;
}

Color? textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

SignalColors colorsOf(WidgetTester tester) =>
    SignalColors.of(tester.element(find.byType(SignalStatusBar)));

void main() {
  group('SignalStatusBar states', () {
    const sending = 'Sending ultrasonic packets';
    final cases = {
      ModemLinkState.idle: ('Idle', 'Ready'),
      ModemLinkState.listening: ('Listening…', '18–20 kHz band active'),
      ModemLinkState.transmitting: ('Transmitting…', sending),
      ModemLinkState.receiving: ('Receiving Frame…', 'Decoding frame…'),
      ModemLinkState.error: ('Error / CRC Failure', 'Ready'),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key.name}: label, subtitle and colour',
          (tester) async {
        await pumpBar(tester, SignalMetrics(connectionState: entry.key));
        final (label, subtitle) = entry.value;
        expect(find.text(label), findsOneWidget);
        expect(find.text(subtitle), findsOneWidget);

        final c = colorsOf(tester);
        final theme = Theme.of(tester.element(find.byType(SignalStatusBar)));
        final expected = switch (entry.key) {
          ModemLinkState.receiving => c.success,
          ModemLinkState.transmitting => theme.colorScheme.primary,
          ModemLinkState.listening => c.info,
          ModemLinkState.error => c.danger,
          ModemLinkState.idle => c.neutral,
        };
        expect(textColor(tester, label), expected);
      });
    }
  });

  group('SignalStatusBar readouts', () {
    testWidgets('SNR colour bands: low, moderate, good', (tester) async {
      await pumpBar(tester, SignalMetrics(snr: 3.0));
      expect(textColor(tester, '3.0 dB'), colorsOf(tester).danger);

      await pumpBar(tester, SignalMetrics(snr: 8.5));
      expect(textColor(tester, '8.5 dB'), colorsOf(tester).warning);

      await pumpBar(tester, SignalMetrics(snr: 20.0));
      expect(textColor(tester, '20.0 dB'), colorsOf(tester).success);

      await pumpBar(tester, SignalMetrics(snr: 0.0));
      expect(textColor(tester, '--- dB'), colorsOf(tester).neutral);
    });

    testWidgets('frame errors take precedence over the decoded badge',
        (tester) async {
      final m =
          SignalMetrics(framesReceived: 5, framesDetected: 8, frameErrors: 3);
      await pumpBar(tester, m);
      expect(find.text('Err: 3'), findsOneWidget);
      expect(find.text('Rx: 5'), findsNothing);
      expect(find.byTooltip('Frame errors detected (3 / 8)'), findsOneWidget);
      expect(textColor(tester, 'Err: 3'), colorsOf(tester).danger);
    });

    testWidgets('decoded badge when frames arrive without errors',
        (tester) async {
      final m = SignalMetrics(framesReceived: 7, framesDetected: 7);
      await pumpBar(tester, m);
      expect(find.text('Rx: 7'), findsOneWidget);
      expect(find.byTooltip('Frames decoded: 7'), findsOneWidget);
      expect(find.textContaining('Err:'), findsNothing);
    });

    testWidgets('no badge before any frame', (tester) async {
      await pumpBar(tester, SignalMetrics());
      expect(find.textContaining('Rx:'), findsNothing);
      expect(find.textContaining('Err:'), findsNothing);
    });

    testWidgets('throughput formats bps and kbps', (tester) async {
      await pumpBar(tester, SignalMetrics(bitsPerSecond: 450));
      expect(find.text('450 bps'), findsOneWidget);
      await pumpBar(tester, SignalMetrics(bitsPerSecond: 1234));
      expect(find.text('1.2 kbps'), findsOneWidget);
    });

    testWidgets('AGC readout shows signed gain only when AGC is active',
        (tester) async {
      await pumpBar(tester, SignalMetrics(agcGainDb: 12.4));
      expect(find.text('AGC +12 dB'), findsOneWidget);
      await pumpBar(tester, SignalMetrics(agcGainDb: -6.0));
      expect(find.text('AGC -6 dB'), findsOneWidget);
      await pumpBar(tester, SignalMetrics());
      expect(find.byKey(const Key('agc_gain_readout')), findsNothing);
    });

    testWidgets('reduce motion: the status dot does not pulse',
        (tester) async {
      final m = SignalMetrics(connectionState: ModemLinkState.listening);
      await pumpBar(tester, m, reduceMotion: true);
      // With animations disabled nothing is scheduled, so the tree settles.
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
    });

    testWidgets('dark theme uses the dark signal palette', (tester) async {
      final m = SignalMetrics(connectionState: ModemLinkState.error);
      await pumpBar(tester, m, theme: SoundwaveTheme.dark);
      final danger = SignalColors.dark.danger;
      expect(colorsOf(tester).danger, danger);
      expect(textColor(tester, 'Error / CRC Failure'), danger);
    });
  });
}
