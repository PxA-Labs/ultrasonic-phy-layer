// Widget tests for SignalStatusBar

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/widgets/signal_status_bar.dart';
import '../engine/mock_native.dart';

Widget createTestBar({required AppState state, bool compact = false}) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SignalStatusBar(compact: compact),
        ),
      ),
    );

void main() {
  group('SignalStatusBar Widget', () {
    testWidgets('renders idle state with placeholders by default',
        (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(createTestBar(state: state));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('--- bps'), findsOneWidget);
      expect(find.text('--- dB'), findsOneWidget);
      expect(find.text('SNR'), findsOneWidget);

      state.dispose();
    });

    testWidgets('renders listening state when toggled', (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(createTestBar(state: state));
      await tester.pump(const Duration(milliseconds: 50));

      state.toggleListening();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Listening…'), findsOneWidget);
      expect(find.text('18–20 kHz band active'), findsOneWidget);

      state.toggleListening();
      state.dispose();
    });

    testWidgets('renders error badge when frame errors occur', (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(createTestBar(state: state));
      await tester.pump(const Duration(milliseconds: 50));

      state.toggleListening();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SignalStatusBar), findsOneWidget);

      state.toggleListening();
      state.dispose();
    });

    testWidgets('renders compact mode without SNR bar', (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(createTestBar(state: state, compact: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('SNR'), findsNothing);

      state.dispose();
    });
  });
}
