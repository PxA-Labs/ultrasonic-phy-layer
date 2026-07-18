// Unit tests for AppState
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/state/app_state.dart';

void main() {
  group('AppState', () {
    test('default values', () {
      final state = AppState();
      expect(state.sampleRate, 44100);
      expect(state.mode, 0);
      expect(state.sf, 8);
      expect(state.numSubcarriers, 256);
      expect(state.cpLength, 64);
      expect(state.isListening, false);
      expect(state.messages, isEmpty);
    });

    test('setMode toggles mode', () {
      final state = AppState();
      state.setMode(1);
      expect(state.mode, 1);
    });

    test('setSf sets spreading factor', () {
      final state = AppState();
      state.setSf(12);
      expect(state.sf, 12);
    });

    test('addMessage prepends and caps at 100', () {
      final state = AppState();
      for (int i = 0; i < 101; i++) {
        state.addMessage('msg$i', i.toDouble());
      }
      expect(state.messages.length, 100);
      expect(state.messages.first, contains('msg100'));
    });

    test('loadPreset long_range sets sf=12 mode=0', () {
      final state = AppState();
      state.loadPreset('long_range');
      expect(state.mode, 0);
      expect(state.sf, 12);
    });

    test('loadPreset high_speed sets mode=1 nsc=2048', () {
      final state = AppState();
      state.loadPreset('high_speed');
      expect(state.mode, 1);
      expect(state.numSubcarriers, 2048);
    });
  });
}
