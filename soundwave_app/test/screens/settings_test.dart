// Flutter widget tests for Settings screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/settings.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

Widget createApp() => ChangeNotifierProvider(
      create: (_) => AppState(audio: MockAudioService()),
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  group('SettingsScreen', () {
    testWidgets('renders mode selector and CSS settings', (tester) async {
      await tester.pumpWidget(createApp());
      expect(find.textContaining('CSS'), findsWidgets);
      expect(find.textContaining('OFDM'), findsWidgets);
      expect(find.text('Spreading Factor (SF): 8'), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget);
    });

    testWidgets('switching to OFDM shows FFT options', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.tap(find.text('OFDM (Orthogonal Freq Division)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FFT Size: 256'), findsOneWidget);
    });

    testWidgets('BPSK/QPSK selector updates AppState', (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.tap(find.text('OFDM (Orthogonal Freq Division)'));
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('ofdm_modulation_selector'));
      await tester.ensureVisible(selector);
      expect(state.ofdmModulation, 1); // QPSK default
      await tester.tap(find.text('BPSK (robust)'));
      await tester.pumpAndSettle();
      expect(state.ofdmModulation, 0);
      expect(state.configMap['ofdm_modulation'], 0);
    });

    testWidgets('large FFT preset renders with a valid CP selection',
        (tester) async {
      // Previously cp stayed 64 when N became 2048, a value outside the
      // CP dropdown items (512/256/128), which asserts in DropdownButton.
      final state = AppState(audio: MockAudioService())
        ..setMode(1)
        ..setNumSubcarriers(256)
        ..setCpLength(64);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      state.setNumSubcarriers(2048);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('(512)'), findsOneWidget); // 1/4 of 2048
    });

    testWidgets('AGC switch toggles AppState', (tester) async {
      final state = AppState(audio: MockAudioService());
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      final toggle = find.byKey(const Key('agc_toggle'));
      // The settings list builds lazily: scroll until the audio card exists.
      await tester.scrollUntilVisible(toggle, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(state.agcEnabled, isTrue);
      await tester
          .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(state.agcEnabled, isFalse);
      expect(state.configMap['agc_enabled'], isFalse);
    });

    testWidgets('load presets', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.tap(find.textContaining('Long Range'));
      await tester.pumpAndSettle();
      expect(find.text('Spreading Factor (SF): 12'), findsOneWidget);
    });
  });
}
