// Flutter widget tests for Dashboard screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/dashboard.dart';
import 'package:soundwave/state/app_state.dart';

Widget createApp() => ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MaterialApp(home: DashboardScreen()),
    );

void main() {
  group('DashboardScreen', () {
    testWidgets('renders tx and rx sections', (tester) async {
      await tester.pumpWidget(createApp());
      expect(find.textContaining('Soundwave'), findsWidgets);
      expect(find.text('Transmission Control'), findsOneWidget);
      expect(find.text('Receiver Control'), findsOneWidget);
      expect(find.text('Received Messages Log'), findsOneWidget);
    });

    testWidgets('send button disabled when empty', (tester) async {
      await tester.pumpWidget(createApp());
      final sendBtn =
          find.widgetWithText(ElevatedButton, 'Send / Modulate & Play');
      expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNull);
    });
  });
}
