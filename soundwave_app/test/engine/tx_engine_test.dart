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
      expect(txEngine.totalBytesSent, equals(5));
      expect(txEngine.framesSent, equals(1));
    });

    test('sendMessage emits TxMetrics event on stream', () async {
      final emitted = <dynamic>[];
      final sub = txEngine.metrics.listen(emitted.add);

      await txEngine.sendMessage('world');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emitted.length, equals(1));
      expect(emitted.first.bytesSent, equals(5));
      await sub.cancel();
    });
  });
}
