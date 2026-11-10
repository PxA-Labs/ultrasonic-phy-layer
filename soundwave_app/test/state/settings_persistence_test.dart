// Persistence of modem settings through SettingsStore.

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/settings_store.dart';
import '../engine/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState settings persistence', () {
    test('setters save and a new AppState restores them', () async {
      final store = InMemorySettingsStore();
      final a = AppState(audio: MockAudioService(), store: store);
      a.setMode(1);
      a.setNumSubcarriers(1024);
      a.setOfdmModulation(0);
      a.setEnableRs(false);
      await Future<void>.delayed(Duration.zero);
      expect(store.saveCount, greaterThan(0));

      final b = AppState(audio: MockAudioService(), store: store);
      await b.restoreSettings();
      expect(b.mode, 1);
      expect(b.numSubcarriers, 1024);
      expect(b.ofdmModulation, 0);
      expect(b.enableRs, false);
      expect(b.configMap['num_subcarriers'], 1024);
      expect(b.configMap['ofdm_modulation'], 0);
      a.dispose();
      b.dispose();
    });

    test('AGC toggle defaults on, persists, and clears the gain readout',
        () async {
      final store = InMemorySettingsStore();
      final a = AppState(audio: MockAudioService(), store: store);
      expect(a.agcEnabled, isTrue);
      expect(a.configMap['agc_enabled'], isTrue);
      a.setAgcEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(store.values['agc_enabled'], false);
      expect(a.metrics.agcGainDb, isNull);

      final b = AppState(audio: MockAudioService(), store: store);
      await b.restoreSettings();
      expect(b.agcEnabled, isFalse);
      expect(b.configMap['agc_enabled'], isFalse);
      a.dispose();
      b.dispose();
    });

    test('presets are persisted', () async {
      final store = InMemorySettingsStore();
      final a = AppState(audio: MockAudioService(), store: store)
        ..loadPreset('high_speed');
      await Future<void>.delayed(Duration.zero);
      expect(store.values['modulation'], 1);
      expect(store.values['num_subcarriers'], 2048);
      a.dispose();
    });

    test('tampered or corrupt values are ignored on restore', () async {
      final store = InMemorySettingsStore({
        'modulation': 7, // invalid
        'sf': 30, // invalid
        'num_subcarriers': 100, // not an offered FFT size
        'symbol_duration': double.nan, // non-finite
        'carrier_freq': 'loud', // wrong type
        'amplitude': 0.5, // valid
        'enable_rs': false, // valid
      });
      final s = AppState(audio: MockAudioService(), store: store);
      await s.restoreSettings();
      expect(s.mode, 0);
      expect(s.sf, 8);
      expect(s.numSubcarriers, 256);
      expect(s.symbolDuration, 0.02);
      expect(s.carrierFreq, 19000.0);
      expect(s.amplitude, 0.5);
      expect(s.enableRs, false);
      s.dispose();
    });

    test('changing FFT size keeps the cyclic-prefix fraction', () {
      final s = AppState(audio: MockAudioService());
      s.setNumSubcarriers(256);
      s.setCpLength(64); // N/4
      s.setNumSubcarriers(2048);
      expect(s.cpLength, 512);
      s.setCpLength(128); // N/16
      s.setNumSubcarriers(512);
      expect(s.cpLength, 32);
      expect(AppState.cpOptionsFor(512), contains(s.cpLength));
      s.dispose();
    });

    test('works without a store (no persistence)', () async {
      final s = AppState(audio: MockAudioService());
      s.setMode(1);
      await s.restoreSettings(); // no-op
      expect(s.mode, 1);
      s.dispose();
    });
  });

  group('ModemSettingsSchema', () {
    test('carrier above Nyquist for the stored sample rate is rejected', () {
      final v = ModemSettingsSchema.sanitize(
          {'sample_rate': 16000, 'carrier_freq': 19000.0});
      expect(v['sample_rate'], 16000);
      expect(v.containsKey('carrier_freq'), isFalse);
    });

    test('cp must fit the stored FFT size', () {
      final v = ModemSettingsSchema.sanitize(
          {'num_subcarriers': 256, 'cp_length': 512});
      expect(v.containsKey('cp_length'), isFalse);
    });
  });
}
