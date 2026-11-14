// Persistence of theme mode and the onboarding flag through SettingsStore.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/state/settings_store.dart';
import 'package:soundwave/state/ui_preferences.dart';

class FailingSettingsStore implements SettingsStore {
  @override
  Future<Map<String, Object>> load() async => throw StateError('corrupt');

  @override
  Future<void> save(Map<String, Object> values) async =>
      throw StateError('read-only');
}

void main() {
  group('UiPreferences', () {
    test('defaults to system theme with onboarding pending', () {
      final prefs = UiPreferences();
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.onboardingComplete, isFalse);
      expect(prefs.isLoaded, isTrue); // nothing to load without a store
      prefs.dispose();
    });

    test('is not loaded until restore() completes', () async {
      final prefs = UiPreferences(store: InMemorySettingsStore());
      expect(prefs.isLoaded, isFalse);
      await prefs.restore();
      expect(prefs.isLoaded, isTrue);
      prefs.dispose();
    });

    test('changes are saved and restored by a new instance', () async {
      final store = InMemorySettingsStore();
      final a = UiPreferences(store: store);
      await a.restore();
      var notifications = 0;
      a.addListener(() => notifications++);
      a.setThemeMode(ThemeMode.dark);
      a.completeOnboarding();
      a.setThemeMode(ThemeMode.dark); // unchanged: no save, no notify
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
      expect(store.values, {
        UiPreferences.themeModeKey: 'dark',
        UiPreferences.onboardingKey: true,
      });

      final b = UiPreferences(store: store);
      await b.restore();
      expect(b.themeMode, ThemeMode.dark);
      expect(b.onboardingComplete, isTrue);
      a.dispose();
      b.dispose();
    });

    test('tampered values are ignored', () async {
      final prefs = UiPreferences(
        store: InMemorySettingsStore({
          UiPreferences.themeModeKey: 'purple',
          UiPreferences.onboardingKey: 'yes',
        }),
      );
      await prefs.restore();
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.onboardingComplete, isFalse);
      prefs.dispose();
    });

    test('a failing store falls back to defaults and still loads', () async {
      final prefs = UiPreferences(store: FailingSettingsStore());
      await prefs.restore();
      expect(prefs.isLoaded, isTrue);
      expect(prefs.onboardingComplete, isFalse);
      prefs.setThemeMode(ThemeMode.light); // save error is swallowed
      await Future<void>.delayed(Duration.zero);
      expect(prefs.themeMode, ThemeMode.light);
      prefs.dispose();
    });

    test('parseThemeMode accepts only known names', () {
      expect(UiPreferences.parseThemeMode('light'), ThemeMode.light);
      expect(UiPreferences.parseThemeMode('system'), ThemeMode.system);
      expect(UiPreferences.parseThemeMode('Dark'), isNull);
    });
  });
}
