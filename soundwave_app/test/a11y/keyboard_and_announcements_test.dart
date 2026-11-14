// Keyboard navigation, live announcements and the DSP status badge (#93).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/native/native_status.dart';
import 'package:soundwave/screens/dashboard.dart';
import 'package:soundwave/screens/monitor.dart';
import 'package:soundwave/screens/settings.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/ui_preferences.dart';
import 'package:soundwave/theme/soundwave_theme.dart';
import 'package:soundwave/widgets/viz/spectrum_analyzer_widget.dart';

import '../engine/mock_native.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<AppState> pumpShell(WidgetTester tester, {NativeStatus? native}) async {
  final state = AppState(
    audio: MockAudioService(),
    nativeProbe: () => native ?? const NativeStatus.loaded('1.0.0'),
  );
  await tester.pumpWidget(SoundwaveApp(
    appState: state,
    uiPreferences: UiPreferences(onboardingComplete: true),
  ));
  await settle(tester);
  return state;
}

/// Which screen (or the navigation bar) holds the primary focus.
String focusOwner() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return 'none';
  if (ctx.findAncestorWidgetOfExactType<NavigationBar>() != null) return 'nav';
  if (ctx.findAncestorWidgetOfExactType<DashboardScreen>() != null) {
    return 'dashboard';
  }
  if (ctx.findAncestorWidgetOfExactType<MonitorScreen>() != null) {
    return 'monitor';
  }
  if (ctx.findAncestorWidgetOfExactType<SettingsScreen>() != null) {
    return 'settings';
  }
  return 'other';
}

int selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

Future<List<String>> tabThrough(WidgetTester tester, int presses) async {
  final owners = <String>[];
  for (var i = 0; i < presses; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    owners.add(focusOwner());
  }
  return owners;
}

void main() {
  group('keyboard navigation', () {
    testWidgets(
        'Tab visits the visible screen, then the nav bar, never a '
        'hidden tab', (tester) async {
      await pumpShell(tester);
      final owners = await tabThrough(tester, 60);
      expect(owners, isNot(contains('monitor')));
      expect(owners, isNot(contains('settings')));
      expect(owners, contains('dashboard'));
      expect(owners, contains('nav'));
      // Content first: the first nav stop comes after a run of dashboard
      // stops, and focus returns to the dashboard after the nav bar.
      final firstNav = owners.indexOf('nav');
      expect(owners.sublist(0, firstNav).toSet(), {'dashboard'});
      expect(owners.sublist(firstNav).contains('dashboard'), isTrue);
    });

    testWidgets('the message field comes before the Send button',
        (tester) async {
      await pumpShell(tester);
      String? first;
      for (var i = 0; i < 30 && first == null; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final w = FocusManager.instance.primaryFocus?.context?.widget;
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx?.findAncestorWidgetOfExactType<TextField>() != null ||
            w is EditableText) {
          first = 'field';
        } else if (ctx?.findAncestorWidgetOfExactType<FilledButton>() != null ||
            ctx?.findAncestorWidgetOfExactType<ElevatedButton>() != null) {
          first = 'button';
        }
      }
      expect(first, 'field');
    });

    testWidgets('Ctrl/Cmd + 1..3 switch tabs and keep focus on the new tab',
        (tester) async {
      await pumpShell(tester);
      expect(selectedTab(tester), 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(selectedTab(tester), 1);
      final owners = await tabThrough(tester, 20);
      expect(owners, isNot(contains('dashboard')));
      expect(owners, contains('monitor'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(selectedTab(tester), 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);
      expect(selectedTab(tester), 0);
    });

    testWidgets('nav destinations advertise their shortcut', (tester) async {
      await pumpShell(tester);
      expect(find.byTooltip('Monitor (Ctrl+2)'), findsOneWidget);
    });
  });

  group('Monitor announcements', () {
    testWidgets('a signal in the band is announced once via a live region',
        (tester) async {
      final handle = tester.ensureSemantics();
      final audio = MockAudioService();
      final state = AppState(audio: audio);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: MonitorScreen()),
      ));
      await tester.pump();
      expect(find.text('No ultrasonic signal'), findsOneWidget);
      final live = tester.getSemantics(find.byKey(const Key('band_activity')));
      expect(live.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

      const hz = 441 * 44100 / 1024; // bin-centred 18.99 kHz
      audio.pushMockChunk(Float64List.fromList(List.generate(
          4096, (i) => 0.25 * math.sin(2 * math.pi * hz * i / 44100))));
      await tester.pump(const Duration(milliseconds: 50));
      // Spectrum bins hold sinusoid amplitude: 20*log10(0.25) = -12 dBFS
      // (the level meter's -15 dBFS is the RMS of the waveform).
      const announced = 'Ultrasonic signal at 19.0 kHz, -12 dBFS';
      expect(find.text(announced), findsOneWidget);
      // The plot exposes the same summary as its value when focused.
      final plot = tester
          .getSemantics(find.byType(SpectrumAnalyzerWidget))
          .getSemanticsData();
      expect(plot.label, 'Spectrum analyzer: signal level by frequency');
      expect(plot.value, announced);

      // 1.2 s of silence in capture-sized chunks (46 ms) ends it: the
      // detector holds for 1 s so gaps between frames do not flap it.
      for (var i = 0; i < 26; i++) {
        audio.pushMockChunk(Float64List(2048));
        await tester.pump(const Duration(milliseconds: 10));
        if (i == 15) expect(find.text(announced), findsOneWidget); // ~0.7 s
      }
      expect(find.text('No ultrasonic signal'), findsOneWidget);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('DSP status badge', () {
    testWidgets('loaded: version in success colour', (tester) async {
      await pumpShell(tester);
      expect(find.text('DSP 1.0.0'), findsOneWidget);
      final icon =
          tester.widget<Icon>(find.byKey(const Key('native_status_icon')));
      expect(icon.icon, Icons.check_circle);
      expect(icon.color, SignalColors.light.success);
    });

    testWidgets('unavailable: says so in danger colour, with the reason',
        (tester) async {
      await pumpShell(tester,
          native: const NativeStatus.unavailable('libsoundwave.so not found'));
      expect(find.text('DSP unavailable'), findsOneWidget);
      final icon =
          tester.widget<Icon>(find.byKey(const Key('native_status_icon')));
      expect(icon.icon, Icons.error);
      expect(icon.color, SignalColors.light.danger);
      final tip = tester.widget<Tooltip>(find.ancestor(
          of: find.text('DSP unavailable'), matching: find.byType(Tooltip)));
      expect(tip.message, contains('libsoundwave.so not found'));
    });

    testWidgets('badge follows the dark theme', (tester) async {
      final state = AppState(
        audio: MockAudioService(),
        nativeProbe: () => const NativeStatus.loaded('1.0.0'),
      );
      await tester.pumpWidget(SoundwaveApp(
        appState: state,
        uiPreferences:
            UiPreferences(themeMode: ThemeMode.dark, onboardingComplete: true),
      ));
      await settle(tester);
      final icon =
          tester.widget<Icon>(find.byKey(const Key('native_status_icon')));
      expect(icon.color, SignalColors.dark.success);
    });

    test('probe() reports a load failure instead of throwing', () {
      final s = NativeStatus.probe();
      expect(s.isLoaded, s.error == null);
      if (s.isLoaded) expect(s.version, isNotEmpty);
    });
  });
}
