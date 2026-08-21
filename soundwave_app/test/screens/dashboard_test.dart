// Flutter widget tests for Dashboard screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/screens/dashboard.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

Widget createApp() => ChangeNotifierProvider(
      create: (_) => AppState(audio: MockAudioService()),
      child: const MaterialApp(home: DashboardScreen()),
    );

void main() {
  group('DashboardScreen', () {
    testWidgets('renders tx and rx sections', (tester) async {
      await tester.pumpWidget(createApp());
      expect(find.textContaining('Soundwave'), findsWidgets);
      expect(find.text('Transmission Control'), findsOneWidget);
      expect(find.text('Receiver Control'), findsOneWidget);
      
      // Scroll down to bring the _MessagesLog card into view
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.textContaining('Received Messages'), findsWidgets);
    });

    testWidgets('send button disabled when empty', (tester) async {
      await tester.pumpWidget(createApp());
      final sendBtn =
          find.widgetWithText(ElevatedButton, 'Send / Modulate & Play');
      expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNull);
    });
  });
}
