// Accessibility checks for the main screens (issue #93): Flutter's
// tap-target, label and text-contrast guidelines in both themes, 200% text
// scaling without overflow, live-region announcement of received messages,
// and theme switching.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/ui_preferences.dart';
import 'package:soundwave/theme/soundwave_theme.dart';

import '../engine/mock_native.dart';

const tabs = ['Dashboard', 'Monitor', 'Settings'];

UiPreferences completedPrefs(ThemeMode mode) {
  return UiPreferences(themeMode: mode, onboardingComplete: true);
}

Future<AppState> pumpApp(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
  UiPreferences? prefs,
}) async {
  final state = AppState(audio: MockAudioService());
  await tester.pumpWidget(SoundwaveApp(
    appState: state,
    uiPreferences: prefs ?? completedPrefs(themeMode),
  ));
  await tester.pump();
  return state;
}

/// Pumps fixed steps: the dashboard's status dot pulses forever, so
/// pumpAndSettle would time out.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> openTab(WidgetTester tester, String label) async {
  final nav = find.byType(NavigationBar);
  await tester.tap(find.descendant(of: nav, matching: find.text(label)));
  await settle(tester);
}

Future<void> expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final tab in tabs) {
      testWidgets('$tab meets accessibility guidelines (${mode.name})',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, themeMode: mode);
        await openTab(tester, tab);
        await expectGuidelines(tester);
        if (tab == 'Settings') {
          // Also check the bottom of the list (theme selector, tutorial).
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -5000),
          );
          await settle(tester);
          expect(find.byKey(const Key('show_tutorial')), findsOneWidget);
          await expectGuidelines(tester);
        }
        handle.dispose();
      });
    }
  }

  testWidgets('dashboard with live data meets guidelines (dark)',
      (tester) async {
    final handle = tester.ensureSemantics();
    final state = await pumpApp(tester, themeMode: ThemeMode.dark);
    state.addMessage('hello', 14.0);
    state.toggleListening();
    await settle(tester);
    await expectGuidelines(tester);
    state.toggleListening();
    await settle(tester);
    handle.dispose();
  });

  testWidgets('main screens lay out at 200% text scale without overflow',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = await pumpApp(tester);
    state.addMessage('a reasonably long message received over sound', 7.5);
    await settle(tester);
    final title = find.text('Soundwave Dashboard');
    expect(MediaQuery.textScalerOf(tester.element(title)).scale(10), 20);
    expect(tester.takeException(), isNull);

    for (final tab in tabs) {
      await openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
    // The OFDM card replaces the CSS card in Settings.
    state.setMode(1);
    await settle(tester);
    expect(find.textContaining('FFT Size'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // And the bottom of the settings list.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('received messages are announced through a live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    final state = await pumpApp(tester);
    final region = find.byKey(const Key('rx_live_region'));
    expect(region, findsNothing);

    state.addMessage('ping', 9.0);
    await settle(tester);
    expect(tester.getSemantics(region), isSemantics(isLiveRegion: true));
    expect(tester.getSemantics(region).label, contains('"ping"'));

    state.addMessage('pong', 9.0);
    await settle(tester);
    expect(tester.getSemantics(region).label, contains('"pong"'));
    handle.dispose();
  });

  testWidgets('icon-only controls have tooltips and custom paints labels',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await openTab(tester, 'Monitor');
    expect(find.byTooltip('Pause monitor'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Live waveform of the microphone input'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Waterfall spectrogram'), findsOneWidget);
    final level = tester.getSemantics(find.byType(LinearProgressIndicator));
    expect(level.label, contains('Input level'));
    handle.dispose();
  });

  testWidgets('theme follows the system and the Settings selector',
      (tester) async {
    final prefs = UiPreferences(onboardingComplete: true);
    await pumpApp(tester, prefs: prefs);
    Brightness brightnessOf(String text) {
      return Theme.of(tester.element(find.text(text))).brightness;
    }

    expect(prefs.themeMode, ThemeMode.system);
    expect(brightnessOf('Soundwave Dashboard'), Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await settle(tester);
    expect(brightnessOf('Soundwave Dashboard'), Brightness.dark);
    final context = tester.element(find.text('Soundwave Dashboard'));
    final surface = Theme.of(context).colorScheme.surface;
    expect(surface, SoundwaveTheme.darkScheme.surface);

    // A manual choice overrides the (dark) system setting.
    await openTab(tester, 'Settings');
    final selector = find.byKey(const Key('theme_mode_selector'));
    await tester.scrollUntilVisible(selector, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Light'));
    await settle(tester);
    expect(prefs.themeMode, ThemeMode.light);
    expect(brightnessOf('Settings & Configuration'), Brightness.light);

    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(prefs.themeMode, ThemeMode.dark);
    expect(brightnessOf('Settings & Configuration'), Brightness.dark);
  });
}
