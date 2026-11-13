// Onboarding tutorial: navigation, permission step, first-run gating,
// replay from Settings and accessibility.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/onboarding/onboarding_screen.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/settings_store.dart';
import 'package:soundwave/state/ui_preferences.dart';
import 'package:soundwave/theme/soundwave_theme.dart';

import '../engine/mock_native.dart';

Future<bool> grantMic() async => true;

Widget host({
  required VoidCallback onFinished,
  Future<bool> Function() requestMic = grantMic,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? SoundwaveTheme.light,
    home: OnboardingScreen(
      onFinished: onFinished,
      requestMicPermission: requestMic,
    ),
  );
}

Future<void> tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboarding_next')));
  await tester.pumpAndSettle();
}

/// Lets route and page transitions finish without pumpAndSettle (the
/// dashboard's status dot pulses forever once the main shell is shown).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  test('pages cover TX/RX, CSS vs OFDM and the microphone rationale', () {
    final titles = onboardingPages.map((p) => p.title).toList();
    expect(titles.first, 'Welcome to Soundwave');
    expect(titles, contains('How it works'));
    expect(titles, contains('CSS or OFDM'));
    expect(titles, contains('Microphone access'));
    final text = onboardingPages.expand((p) => p.body).join(' ');
    expect(text, contains('Transmit:'));
    expect(text, contains('Receive:'));
    expect(text, contains('Chirp Spread Spectrum'));
    expect(onboardingPages.where((p) => p.asksMicPermission), hasLength(1));
  });

  group('OnboardingScreen', () {
    testWidgets('Next walks every page and Get started finishes',
        (tester) async {
      var finished = 0;
      await tester.pumpWidget(host(onFinished: () => finished++));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Soundwave'), findsOneWidget);
      expect(find.text('Step 1 of ${onboardingPages.length}'), findsOneWidget);

      for (var i = 1; i < onboardingPages.length; i++) {
        await tapNext(tester);
        expect(find.text(onboardingPages[i].title), findsOneWidget);
      }
      expect(find.text('Get started'), findsOneWidget);
      expect(finished, 0);
      await tapNext(tester);
      expect(finished, 1);
    });

    testWidgets('Skip finishes from the first page', (tester) async {
      var finished = false;
      await tester.pumpWidget(host(onFinished: () => finished = true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_skip')));
      await tester.pump();
      expect(finished, isTrue);
    });

    testWidgets('back button returns to the previous page', (tester) async {
      await tester.pumpWidget(host(onFinished: () {}));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous page'), findsNothing);
      await tapNext(tester);
      expect(find.text('How it works'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Soundwave'), findsOneWidget);
    });

    testWidgets('microphone step requests permission and announces result',
        (tester) async {
      final handle = tester.ensureSemantics();
      var requests = 0;
      Future<bool> deny() async {
        requests++;
        return false;
      }

      await tester.pumpWidget(host(onFinished: () {}, requestMic: deny));
      await tester.pumpAndSettle();
      final micPage = onboardingPages.indexWhere((p) => p.asksMicPermission);
      for (var i = 0; i < micPage; i++) {
        await tapNext(tester);
      }
      expect(find.text('Microphone access'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_allow_mic')));
      await tester.pumpAndSettle();
      expect(requests, 1);
      final result = find.byKey(const Key('onboarding_mic_result'));
      expect(find.textContaining('not granted'), findsOneWidget);
      expect(
        tester.getSemantics(result),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });

    testWidgets('a throwing permission request is reported as not granted',
        (tester) async {
      Future<bool> broken() async => throw StateError('no plugin');
      await tester.pumpWidget(host(onFinished: () {}, requestMic: broken));
      await tester.pumpAndSettle();
      final micPage = onboardingPages.indexWhere((p) => p.asksMicPermission);
      for (var i = 0; i < micPage; i++) {
        await tapNext(tester);
      }
      await tester.tap(find.byKey(const Key('onboarding_allow_mic')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not granted'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      final themeName = dark ? 'dark' : 'light';
      testWidgets('every page meets a11y guidelines ($themeName)',
          (tester) async {
        final handle = tester.ensureSemantics();
        final theme = dark ? SoundwaveTheme.dark : SoundwaveTheme.light;
        await tester.pumpWidget(host(onFinished: () {}, theme: theme));
        await tester.pumpAndSettle();
        for (var i = 0; i < onboardingPages.length; i++) {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          if (i < onboardingPages.length - 1) await tapNext(tester);
        }
        handle.dispose();
      });
    }

    testWidgets('every page lays out at 200% text scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(host(onFinished: () {}));
      await tester.pumpAndSettle();
      for (var i = 0; i < onboardingPages.length; i++) {
        expect(tester.takeException(), isNull);
        expect(find.text(onboardingPages[i].title), findsOneWidget);
        if (i < onboardingPages.length - 1) await tapNext(tester);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('first-run gating', () {
    testWidgets('shown on first launch, then persisted as complete',
        (tester) async {
      final store = InMemorySettingsStore();
      final prefs = UiPreferences(store: store);
      await tester.pumpWidget(SoundwaveApp(
        appState: AppState(audio: MockAudioService()),
        uiPreferences: prefs,
      ));
      await prefs.restore();
      await tester.pump();
      expect(find.text('Welcome to Soundwave'), findsOneWidget);
      expect(find.text('Soundwave Dashboard'), findsNothing);

      await tester.tap(find.byKey(const Key('onboarding_skip')));
      await settle(tester);
      expect(find.text('Soundwave Dashboard'), findsOneWidget);
      expect(store.values[UiPreferences.onboardingKey], isTrue);
    });

    testWidgets('not shown once completed', (tester) async {
      final prefs = UiPreferences(
        store: InMemorySettingsStore({UiPreferences.onboardingKey: true}),
      );
      await tester.pumpWidget(SoundwaveApp(
        appState: AppState(audio: MockAudioService()),
        uiPreferences: prefs,
      ));
      await prefs.restore();
      await tester.pump();
      expect(find.text('Soundwave Dashboard'), findsOneWidget);
      expect(find.text('Welcome to Soundwave'), findsNothing);
    });

    testWidgets('can be replayed from Settings', (tester) async {
      await tester.pumpWidget(SoundwaveApp(
        appState: AppState(audio: MockAudioService()),
        uiPreferences: UiPreferences(onboardingComplete: true),
      ));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await settle(tester);

      final tile = find.byKey(const Key('show_tutorial'));
      await tester.scrollUntilVisible(tile, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(tile);
      await settle(tester);
      expect(find.text('Welcome to Soundwave'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_skip')));
      await settle(tester);
      expect(find.text('Welcome to Soundwave'), findsNothing);
      expect(find.text('Settings & Configuration'), findsOneWidget);
    });
  });
}
