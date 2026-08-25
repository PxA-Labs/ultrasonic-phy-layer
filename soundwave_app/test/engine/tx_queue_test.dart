// Unit tests for TxQueue.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/engine/tx_queue.dart';
import 'mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TxQueue Tests', () {
    late MockSoundwaveNative mockNative;
    late MockAudioService mockAudio;
    late TxEngine txEngine;
    late TxQueue txQueue;

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
      txQueue = TxQueue(txEngine: txEngine);
    });

    test('enqueue processes messages sequentially', () async {
      await txQueue.enqueue('msg1');
      await txQueue.enqueue('msg2');

      expect(mockAudio.isPlaying, true);
      expect(mockAudio.playbackQueue, isNotNull);
      expect(mockAudio.playbackQueue!.length, equals(100));
    });

    test('enqueue with future schedule delays transmission', () async {
      // Schedule message 300ms in the future
      final scheduleTime =
          DateTime.now().add(const Duration(milliseconds: 300));

      // Wait for the scheduled transmission to complete.
      // processQueue runs in background; we await it via a separate future
      // that resolves once playback starts.
      final done = Completer<void>();
      mockAudio.onPlaybackStarted = done.complete;

      // Enqueue (non-blocking — processQueue runs internally)
      txQueue.enqueue('scheduled_msg', scheduledAt: scheduleTime);

      final startTime = DateTime.now();
      await done.future;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;

      // Should have waited before transmitting
      expect(elapsed, greaterThanOrEqualTo(150));
      expect(mockAudio.isPlaying, true);
    });
  });
}
