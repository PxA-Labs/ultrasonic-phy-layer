// End-of-transfer toast (#89).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/transfer_notice.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/ui_preferences.dart';
import 'package:soundwave/theme/soundwave_theme.dart';
import 'package:soundwave/widgets/transfer_notice_listener.dart';

import '../engine/mock_native.dart';

void main() {
  late StreamController<TransferNotice> notices;

  setUp(() => notices = StreamController<TransferNotice>.broadcast());
  tearDown(() => notices.close());

  Widget host({ThemeData? theme}) => MaterialApp(
        theme: theme ?? SoundwaveTheme.light,
        home: Scaffold(
          body: TransferNoticeListener(
            notices: notices.stream,
            child: const SizedBox.expand(),
          ),
        ),
      );

  testWidgets('shows a toast with file name, size, time and throughput',
      (tester) async {
    await tester.pumpWidget(host());
    notices.add(const TransferNotice(
      direction: TransferDirection.received,
      fileName: 'photo.png',
      bytes: 12800,
      duration: Duration(seconds: 8),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // slide in
    expect(find.byKey(const Key('transfer_notice')), findsOneWidget);
    expect(
      find.text('Received "photo.png" (12.5 KB) in 8.0 s · 12.8 kbit/s'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('a newer notice replaces the current one; failures say so',
      (tester) async {
    await tester.pumpWidget(host());
    notices.add(const TransferNotice(
      direction: TransferDirection.sent,
      fileName: 'a.bin',
      bytes: 10,
      duration: Duration(seconds: 1),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    notices.add(const TransferNotice(
      direction: TransferDirection.sent,
      fileName: 'b.bin',
      bytes: 10,
      duration: Duration(seconds: 3),
      ok: false,
      error: 'not acknowledged',
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('a.bin'), findsNothing);
    expect(find.text('Sending "b.bin" failed after 3.0 s: not acknowledged'),
        findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('toast meets a11y guidelines in both themes', (tester) async {
    for (final theme in [SoundwaveTheme.light, SoundwaveTheme.dark]) {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(theme: theme));
      notices.add(const TransferNotice(
        direction: TransferDirection.sent,
        fileName: 'a.bin',
        bytes: 2048,
        duration: Duration(seconds: 2),
        retransmissions: 2,
      ));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
      // Let the toast expire before the next theme.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the app shell listens to AppState notices', (tester) async {
    final state = AppState(audio: MockAudioService());
    await tester.pumpWidget(SoundwaveApp(
      appState: state,
      uiPreferences: UiPreferences(onboardingComplete: true),
    ));
    await tester.pump();
    expect(find.byType(TransferNoticeListener), findsOneWidget);
  });
}
