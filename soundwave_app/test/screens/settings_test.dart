// Flutter widget tests for Settings screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/settings.dart';
import 'package:soundwave/state/app_state.dart';

Widget createApp() => ChangeNotifierProvider(
  create: (_) => AppState(),
  child: const MaterialApp(home: SettingsScreen()),
);

void main() {
  group('SettingsScreen', () {
    testWidgets('renders mode selector and CSS settings', (tester) async {
      await tester.pumpWidget(createApp());
      expect(find.text('CSS'), findsWidgets);
      expect(find.text('OFDM'), findsWidgets);
      expect(find.text('Spreading Factor: 8'), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget);
    });

    testWidgets('switching to OFDM shows FFT options', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.tap(find.text('OFDM'));
      await tester.pumpAndSettle();
      expect(find.text('FFT: 256'), findsOneWidget);
    });

    testWidgets('load presets', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.tap(find.text('Long Range'));
      await tester.pumpAndSettle();
      expect(find.text('Spreading Factor: 12'), findsOneWidget);
    });
  });
}
