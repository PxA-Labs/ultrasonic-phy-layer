// Unit tests for TxEngine.

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TxEngine Tests', () {
    late MockSoundwaveNative mockNative;
    late MockAudioService mockAudio;
    late TxEngine txEngine;

    setUp(() {
      mockNative = MockSoundwaveNative();
      mockAudio = MockAudioService();
      txEngine = TxEngine(
        native: mockNative,
        audio: mockAudio,
        configMap: {
          'modulation': 0, // CSS
          'sample_rate': 44100.0,
        },
        useIsolates: false,
      );
    });

    test('sendMessage constructs frame and triggers playback', () async {
      await txEngine.sendMessage('hello');
      expect(mockAudio.isPlaying, true);
      expect(mockAudio.playbackQueue, isNotNull);
      expect(mockAudio.playbackQueue!.length, equals(100));
    });
  });
}
