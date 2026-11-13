// UI preferences (theme mode, first-run onboarding flag).
//
// Kept apart from AppState because AppState's config map is also handed to
// the native DSP layer; these values are presentation-only. They persist
// through the same [SettingsStore] abstraction, under their own key prefix.

import 'package:flutter/material.dart';

import 'settings_store.dart';

class UiPreferences extends ChangeNotifier {
  /// SharedPreferences key namespace for these values.
  static const String storePrefix = 'soundwave.ui.';
  static const String themeModeKey = 'theme_mode';
  static const String onboardingKey = 'onboarding_complete';

  SettingsStore? _store;
  ThemeMode _themeMode = ThemeMode.system;
  bool _onboardingComplete = false;
  bool _loaded = false;
  bool _disposed = false;

  /// Without a [store] nothing is persisted and the preferences count as
  /// loaded immediately (used by tests and previews).
  UiPreferences({
    SettingsStore? store,
    ThemeMode themeMode = ThemeMode.system,
    bool onboardingComplete = false,
  }) {
    _store = store;
    _themeMode = themeMode;
    _onboardingComplete = onboardingComplete;
    _loaded = store == null;
  }

  ThemeMode get themeMode => _themeMode;
  bool get onboardingComplete => _onboardingComplete;

  /// False until [restore] has finished (or failed) reading the store.
  bool get isLoaded => _loaded;

  /// Loads persisted values. Unknown or mistyped values are ignored, and a
  /// failing store leaves the defaults in place (onboarding is then shown).
  Future<void> restore() async {
    final store = _store;
    if (store != null) {
      try {
        final raw = await store.load();
        final mode = raw[themeModeKey];
        if (mode is String) _themeMode = parseThemeMode(mode) ?? _themeMode;
        final done = raw[onboardingKey];
        if (done is bool) _onboardingComplete = done;
      } catch (e) {
        debugPrint('Failed to load UI preferences: $e');
      }
    }
    _loaded = true;
    _notify();
  }

  static ThemeMode? parseThemeMode(String name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _save();
    _notify();
  }

  void completeOnboarding() {
    if (_onboardingComplete) return;
    _onboardingComplete = true;
    _save();
    _notify();
  }

  void _save() {
    final store = _store;
    if (store == null || _disposed) return;
    final values = <String, Object>{
      themeModeKey: _themeMode.name,
      onboardingKey: _onboardingComplete,
    };
    store.save(values).catchError((Object e) {
      debugPrint('Failed to persist UI preferences: $e');
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
