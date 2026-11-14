// Settings persistence for the modem configuration.
//
// AppState depends on the abstract [SettingsStore] so tests can use
// [InMemorySettingsStore]; the app uses [SharedPreferencesSettingsStore].
// Values read back are untrusted (the preferences file can be edited or
// corrupted), so [ModemSettingsSchema.sanitize] drops anything out of range
// before it reaches the native DSP layer.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundwave/engine/frame_geometry.dart';

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

/// Persists settings in SharedPreferences, one key per setting.
///
/// Callers fire [save] without awaiting it (a settings setter saves on every
/// change), so several saves can be in flight at once. Writes are therefore
/// serialised through one queue shared by every instance (they all write the
/// same preferences file): saves issued while a write is running are merged,
/// latest value per key, into a single pending write, and each write applies
/// its whole snapshot without yielding between keys. [load] waits for queued
/// writes first, so a read never observes a half-applied save.
class SharedPreferencesSettingsStore implements SettingsStore {
  /// Key namespace, so independent stores (modem settings, UI preferences)
  /// never overwrite each other's values.
  final String prefix;

  SharedPreferencesSettingsStore({this.prefix = 'soundwave.modem.'});

  /// Tail of the write queue; completes when every queued write has finished.
  static Future<void> _idle = Future<void>.value();

  /// Prefixed values waiting for the next write, merged latest-wins.
  static Map<String, Object>? _pending;
  static Future<void>? _pendingWrite;

  @override
  Future<Map<String, Object>> load() async {
    await _idle;
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
  Future<void> save(Map<String, Object> values) {
    final batch = _pending ??= <String, Object>{};
    for (final e in values.entries) {
      batch['$prefix${e.key}'] = e.value;
    }
    return _pendingWrite ??= _enqueue();
  }

  static Future<void> _enqueue() {
    final write = _idle.then((_) {
      // Detach the batch: saves from now on start the next write.
      final batch = _pending!;
      _pending = null;
      _pendingWrite = null;
      return _write(batch);
    });
    _idle = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  static Future<void> _write(Map<String, Object> batch) async {
    final prefs = await SharedPreferences.getInstance();
    // Issue every set before awaiting any, so the in-memory preferences take
    // the whole snapshot at once.
    final writes = <Future<bool>>[];
    for (final e in batch.entries) {
      final v = e.value;
      if (v is bool) {
        writes.add(prefs.setBool(e.key, v));
      } else if (v is int) {
        writes.add(prefs.setInt(e.key, v));
      } else if (v is double) {
        writes.add(prefs.setDouble(e.key, v));
      } else if (v is String) {
        writes.add(prefs.setString(e.key, v));
      }
    }
    await Future.wait(writes);
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
    // CSS spreading factors the modem supports (native CSS_MIN/MAX_SF).
    intIn('sf', (v) => v >= FrameGeometry.minSf && v <= FrameGeometry.maxSf);
    intIn('num_subcarriers', subcarrierOptions.contains);
    final n = (out['num_subcarriers'] as int?) ?? 256;
    intIn('cp_length', (v) => v > 0 && v <= n);
    intIn('num_pilots', (v) => v > 0 && v <= n ~/ 2);
    intIn('ofdm_modulation', (v) => v == 0 || v == 1);
    intIn('equalizer', (v) => v == 0 || v == 1);
    doubleIn('carrier_freq', (v) => v > 0 && v <= nyquist);
    doubleIn('bandwidth', (v) => v > 0 && v <= nyquist);
    doubleIn('amplitude', (v) => v >= 0 && v <= 1.0);
    doubleIn('threshold', (v) => v > 0 && v <= 100);
    doubleIn('volume', (v) => v >= 0 && v <= 1.0);
    if (raw['enable_rs'] is bool) out['enable_rs'] = raw['enable_rs']!;
    if (raw['agc_enabled'] is bool) out['agc_enabled'] = raw['agc_enabled']!;
    if (raw['arq_enabled'] is bool) out['arq_enabled'] = raw['arq_enabled']!;
    intIn('arq_max_retries', (v) => v == 1 || v == 3 || v == 5);
    intIn('arq_ack_timeout_ms', (v) => v >= 200 && v <= 2000);
    return out;
  }
}
