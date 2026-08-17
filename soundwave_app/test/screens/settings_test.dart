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

    testWidgets('load presets', (tester) async {
      await tester.pumpWidget(createApp());
      await tester.tap(find.textContaining('Long Range'));
      await tester.pumpAndSettle();
      expect(find.text('Spreading Factor (SF): 12'), findsOneWidget);
    });
  });
}
