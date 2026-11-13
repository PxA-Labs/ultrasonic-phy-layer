// Settings persistence for the modem configuration.
//
// AppState depends on the abstract [SettingsStore] so tests can use
// [InMemorySettingsStore]; the app uses [SharedPreferencesSettingsStore].
// Values read back are untrusted (the preferences file can be edited or
// corrupted), so [ModemSettingsSchema.sanitize] drops anything out of range
// before it reaches the native DSP layer.

import 'package:shared_preferences/shared_preferences.dart';

abstract class SettingsStore {
  Future<Map<String, Object>> load();
  Future<void> save(Map<String, Object> values);
}

class InMemorySettingsStore implements SettingsStore {
  final Map<String, Object> values;
  int saveCount = 0;

  InMemorySettingsStore([Map<String, Object>? initial])
      : values = {...?initial};

  @override
  Future<Map<String, Object>> load() async => Map.of(values);

  @override
  Future<void> save(Map<String, Object> newValues) async {
    saveCount++;
    values
      ..clear()
      ..addAll(newValues);
  }
}

class SharedPreferencesSettingsStore implements SettingsStore {
  /// Key namespace, so independent stores (modem settings, UI preferences)
  /// never overwrite each other's values.
  final String prefix;

  SharedPreferencesSettingsStore({this.prefix = 'soundwave.modem.'});

  @override
  Future<Map<String, Object>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final v = prefs.get(key);
      if (v != null) out[key.substring(prefix.length)] = v;
    }
    return out;
  }

  @override
  Future<void> save(Map<String, Object> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in values.entries) {
      final key = '$prefix${e.key}';
      final v = e.value;
      if (v is bool) {
        await prefs.setBool(key, v);
      } else if (v is int) {
        await prefs.setInt(key, v);
      } else if (v is double) {
        await prefs.setDouble(key, v);
      } else if (v is String) {
        await prefs.setString(key, v);
      }
    }
  }
}

/// Allowed values for persisted modem settings. Mirrors the native
/// sw_config_validate() ranges plus the options the Settings screen offers.
class ModemSettingsSchema {
  static const subcarrierOptions = [256, 512, 1024, 2048];

  /// Returns only the entries of [raw] that are well-typed and in range.
  static Map<String, Object> sanitize(Map<String, Object> raw) {
    final out = <String, Object>{};
    int? asInt(Object? v) => v is int ? v : null;
    double? asDouble(Object? v) =>
        v is double ? v : (v is int ? v.toDouble() : null);

    void intIn(String k, bool Function(int) ok) {
      final v = asInt(raw[k]);
      if (v != null && ok(v)) out[k] = v;
    }

    void doubleIn(String k, bool Function(double) ok) {
      final v = asDouble(raw[k]);
      if (v != null && v.isFinite && ok(v)) out[k] = v;
    }

    intIn('sample_rate', (v) => v >= 8000 && v <= 192000);
    final nyquist = ((out['sample_rate'] as int?) ?? 44100) / 2;
    intIn('modulation', (v) => v == 0 || v == 1);
    intIn('sf', (v) => v >= 6 && v <= 12);
    intIn('num_subcarriers', subcarrierOptions.contains);
    final n = (out['num_subcarriers'] as int?) ?? 256;
    intIn('cp_length', (v) => v > 0 && v <= n);
    intIn('num_pilots', (v) => v > 0 && v <= n ~/ 2);
    intIn('ofdm_modulation', (v) => v == 0 || v == 1);
    intIn('equalizer', (v) => v == 0 || v == 1);
    doubleIn('carrier_freq', (v) => v > 0 && v <= nyquist);
    doubleIn('bandwidth', (v) => v > 0 && v <= nyquist);
    doubleIn('symbol_duration', (v) => v > 0 && v <= 1.0);
    doubleIn('amplitude', (v) => v >= 0 && v <= 1.0);
    doubleIn('threshold', (v) => v > 0 && v <= 100);
    doubleIn('coding_rate', (v) => v > 0 && v <= 1.0);
    doubleIn('volume', (v) => v >= 0 && v <= 1.0);
    if (raw['enable_rs'] is bool) out['enable_rs'] = raw['enable_rs']!;
    if (raw['agc_enabled'] is bool) out['agc_enabled'] = raw['agc_enabled']!;
    return out;
  }
}
