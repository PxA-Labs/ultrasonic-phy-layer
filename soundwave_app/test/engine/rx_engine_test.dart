// Unit tests for RxEngine.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RxEngine Tests', () {
    late MockSoundwaveNative mockNative;
    late MockAudioService mockAudio;
    late RxEngine rxEngine;

    setUp(() {
      mockNative = MockSoundwaveNative();
      mockAudio = MockAudioService();
      rxEngine = RxEngine(
        native: mockNative,
        audio: mockAudio,
        configMap: {
          'modulation': 0, // CSS
          'sample_rate': 44100.0,
        },
        useIsolates: false,
      );
    });

    test(
        'startListening triggers capture and processes chunks to decode messages',
        () async {
      final messages = <DecodedMessage>[];
      final subscription = rxEngine.startListening().listen((msg) {
        messages.add(msg);
      });

      // Wait for startCapture to complete and _audioSubscription to register
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockAudio.isCapturing, true);

      // Push 44100 double samples (exactly the 1s required window size)
      final dummyChunk = Float64List(44100);
      mockAudio.pushMockChunk(dummyChunk);

      // Yield event loop execution to let stream and demodulation complete
      await Future<void>.delayed(const Duration(milliseconds: 300));

      rxEngine.stopListening();
      subscription.cancel();

      expect(mockAudio.isCapturing, false);
      expect(messages.length, greaterThanOrEqualTo(1));
      expect(
          messages[0].text,
          equals(
              '\x01\x02\x03')); // matching dummy payload in MockSoundwaveNative
    });

    test('startListening emits metrics state updates', () async {
      final metricsEvents = <dynamic>[];
      final sub = rxEngine.metrics.listen(metricsEvents.add);

      rxEngine.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(metricsEvents.isNotEmpty, true);

      rxEngine.stopListening();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await sub.cancel();
    });
  });
}
