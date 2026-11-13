// SharedPreferencesSettingsStore: the production SettingsStore. Values must
// round-trip with their types, and the prefix must keep the modem settings
// and the UI preferences from reading or overwriting each other's keys.

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
    first.setMode(1);
    first.setNumSubcarriers(512);
    first.setAgcEnabled(false);
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final second = AppState(
        audio: MockAudioService(), store: SharedPreferencesSettingsStore());
    await second.restoreSettings();
    expect(second.mode, 1);
    expect(second.numSubcarriers, 512);
    expect(second.agcEnabled, isFalse);
    second.dispose();
  });

  test('UI preferences and modem settings share one prefs file safely',
      () async {
    const prefix = UiPreferences.storePrefix;
    final uiStore = SharedPreferencesSettingsStore(prefix: prefix);
    final ui = UiPreferences(store: uiStore);
    await ui.restore();
    expect(ui.onboardingComplete, isFalse);
    ui.completeOnboarding();
    await Future<void>.delayed(Duration.zero);

    final modem = SharedPreferencesSettingsStore();
    await modem.save({'sf': 11});
    expect(await modem.load(), {'sf': 11});

    final reloaded = UiPreferences(store: uiStore);
    await reloaded.restore();
    expect(reloaded.onboardingComplete, isTrue);
  });
}
