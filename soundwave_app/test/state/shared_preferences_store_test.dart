// SharedPreferencesSettingsStore: the production SettingsStore. Values must
// round-trip with their types, and the prefix must keep the modem settings
// and the UI preferences from reading or overwriting each other's keys.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/settings_store.dart';
import 'package:soundwave/state/ui_preferences.dart';

import '../engine/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips bool, int, double and String values', () async {
    final store = SharedPreferencesSettingsStore();
    await store.save({
      'enable_rs': false,
      'sf': 9,
      'carrier_freq': 18500.5,
      'label': 'lab bench',
    });
    final loaded = await store.load();
    expect(loaded, {
      'enable_rs': false,
      'sf': 9,
      'carrier_freq': 18500.5,
      'label': 'lab bench',
    });
    expect(loaded['sf'], isA<int>());
    expect(loaded['carrier_freq'], isA<double>());
  });

  test('stores keys under its prefix and ignores other keys', () async {
    SharedPreferences.setMockInitialValues({
      'soundwave.modem.sf': 10,
      'soundwave.ui.theme': 'dark',
      'unrelated': true,
    });
    final modem = SharedPreferencesSettingsStore();
    expect(await modem.load(), {'sf': 10});

    await modem.save({'modulation': 1});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('soundwave.modem.modulation'), 1);
    expect(prefs.getString('soundwave.ui.theme'), 'dark');
    expect(prefs.getBool('unrelated'), isTrue);
  });

  test('independent prefixes do not collide', () async {
    final a = SharedPreferencesSettingsStore(prefix: 'a.');
    final b = SharedPreferencesSettingsStore(prefix: 'b.');
    await a.save({'x': 1});
    await b.save({'x': 2});
    expect(await a.load(), {'x': 1});
    expect(await b.load(), {'x': 2});
  });

  test('a later save overwrites a key', () async {
    final store = SharedPreferencesSettingsStore();
    await store.save({'threshold': 3.0});
    await store.save({'threshold': 4.5});
    expect((await store.load())['threshold'], 4.5);
  });

  test('modem settings survive an app restart through real prefs', () async {
    final first = AppState(
        audio: MockAudioService(), store: SharedPreferencesSettingsStore());
    // Setters save without awaiting, back to back in the same tick.
    first.setMode(1);
    first.setNumSubcarriers(512);
    first.setAgcEnabled(false);
    first.dispose();

    final second = AppState(
        audio: MockAudioService(), store: SharedPreferencesSettingsStore());
    await second.restoreSettings();
    expect(second.mode, 1);
    expect(second.numSubcarriers, 512);
    expect(second.agcEnabled, isFalse);
    second.dispose();
  });

  test('unawaited same-tick saves all persist across a restart', () async {
    // Regression: overlapping saves each wrote their snapshot key by key with
    // an await per key, so a reload saw a mix of old and new values (FFT size
    // came back 256 instead of 512).
    final first = AppState(
        audio: MockAudioService(), store: SharedPreferencesSettingsStore());
    first.setMode(1);
    first.setSf(10);
    first.setNumSubcarriers(512);
    first.setThreshold(4.5);
    first.setEnableRs(false);
    first.setAgcEnabled(false);
    first.setArqMaxRetries(5);
    final cp = first.cpLength;
    first.dispose();

    final second = AppState(
        audio: MockAudioService(), store: SharedPreferencesSettingsStore());
    await second.restoreSettings();
    expect(second.mode, 1);
    expect(second.sf, 10);
    expect(second.numSubcarriers, 512);
    expect(second.cpLength, cp);
    expect(second.threshold, 4.5);
    expect(second.enableRs, isFalse);
    expect(second.agcEnabled, isFalse);
    expect(second.arqMaxRetries, 5);
    second.dispose();

    // The values reached the preferences file, not just the write queue.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('soundwave.modem.num_subcarriers'), 512);
    expect(prefs.getInt('soundwave.modem.modulation'), 1);
    expect(prefs.getBool('soundwave.modem.agc_enabled'), isFalse);
  });

  test('overlapping store saves keep the latest value of every key', () async {
    final store = SharedPreferencesSettingsStore();
    final saves = [
      store.save({'sf': 7, 'num_subcarriers': 256, 'threshold': 1.0}),
      store.save({'sf': 8, 'num_subcarriers': 512}),
      SharedPreferencesSettingsStore().save({'sf': 9}),
      store.save({'threshold': 2.5, 'enable_rs': true}),
    ];
    // A fresh instance (as after a restart) waits for queued writes.
    expect(await SharedPreferencesSettingsStore().load(), {
      'sf': 9,
      'num_subcarriers': 512,
      'threshold': 2.5,
      'enable_rs': true,
    });
    await Future.wait(saves);

    // A save issued while a write is in flight lands after it.
    final inFlight = store.save({'sf': 10});
    await Future<void>.delayed(Duration.zero);
    final next = store.save({'sf': 11});
    await Future.wait([inFlight, next]);
    expect((await store.load())['sf'], 11);
  });

  test('UI preference changes in one tick survive a restart', () async {
    const prefix = UiPreferences.storePrefix;
    final ui =
        UiPreferences(store: SharedPreferencesSettingsStore(prefix: prefix));
    await ui.restore();
    ui.setThemeMode(ThemeMode.dark);
    ui.completeOnboarding();
    ui.dispose();

    final reloaded =
        UiPreferences(store: SharedPreferencesSettingsStore(prefix: prefix));
    await reloaded.restore();
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.onboardingComplete, isTrue);
  });

  test('UI preferences and modem settings share one prefs file safely',
      () async {
    const prefix = UiPreferences.storePrefix;
    final uiStore = SharedPreferencesSettingsStore(prefix: prefix);
    final ui = UiPreferences(store: uiStore);
    await ui.restore();
    expect(ui.onboardingComplete, isFalse);
    ui.completeOnboarding();

    final modem = SharedPreferencesSettingsStore();
    await modem.save({'sf': 11});
    expect(await modem.load(), {'sf': 11});

    final reloaded = UiPreferences(store: uiStore);
    await reloaded.restore();
    expect(reloaded.onboardingComplete, isTrue);
  });
}
