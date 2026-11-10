// Unit tests for RxEngine (mock native layer; see test/native/ for real DSP).

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RxEngine Tests', () {
    late MockSoundwaveNative mockNative;
    late MockAudioService mockAudio;
    late Map<String, dynamic> config;
    late RxEngine rxEngine;

    RxEngine build() => RxEngine(
          native: mockNative,
          audio: mockAudio,
          configMap: config,
          useIsolates: false,
        );

    setUp(() {
      mockNative = MockSoundwaveNative()..framesToDetect = 1;
      mockAudio = MockAudioService();
      config = {'modulation': 1, 'sample_rate': 44100}; // OFDM: short frames
      rxEngine = build();
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    /// Audio long enough for detection plus a frame of [frameBytes] bytes.
    int samplesFor(int frameBytes) {
      final g = FrameGeometry.fromConfig(config);
      return g.searchWindowSamples + g.samplesForFrameBytes(frameBytes);
    }

    test('decodes a frame once enough audio for it has arrived', () async {
      final messages = <DecodedMessage>[];
      final sub = rxEngine.startListening().listen(messages.add);
      await settle();
      expect(mockAudio.isCapturing, true);

      mockAudio.pushMockChunk(Float64List(samplesFor(39)));
      await settle();

      rxEngine.stopListening();
      await sub.cancel();
      expect(mockAudio.isCapturing, false);
      expect(messages, hasLength(1));
      expect(messages[0].text, '\x01\x02\x03');
      expect(rxEngine.framesDetected, 1);
      expect(rxEngine.framesReceived, 1);
      expect(rxEngine.frameErrors, 0);
    });

    test('does not attempt decoding before a minimum frame is buffered',
        () async {
      config['modulation'] = 0; // CSS: a minimum frame >> search window
      rxEngine.startListening();
      await settle();
      final g = FrameGeometry.fromConfig(config);
      mockAudio.pushMockChunk(Float64List(g.searchWindowSamples));
      await settle();
      expect(rxEngine.framesDetected, 1);
      expect(mockNative.demodCalls, 0);
      rxEngine.stopListening();
    });

    test('assembles a frame delivered across many small chunks', () async {
      final messages = <DecodedMessage>[];
      final sub = rxEngine.startListening().listen(messages.add);
      await settle();
      final total = samplesFor(39);
      for (var sent = 0; sent < total; sent += 256) {
        mockAudio.pushMockChunk(Float64List(256));
        await Future<void>.delayed(Duration.zero);
      }
      await settle();
      rxEngine.stopListening();
      await sub.cancel();
      expect(messages, hasLength(1));
    });

    test('reports a frame error after the longest frame fails to verify',
        () async {
      mockNative.demodOutput = Uint8List.fromList(List.filled(300, 0x5A));
      mockNative.framesToDetect = 1 << 30;
      final events = <RxFrameEvent>[];
      final sub = rxEngine.frameEvents.listen(events.add);
      rxEngine.startListening();
      await settle();

      final g = FrameGeometry.fromConfig(config);
      mockAudio.pushMockChunk(Float64List(
          g.searchWindowSamples + g.maxFrameSamples + 4 * g.samplesPerSymbol));
      await settle();

      rxEngine.stopListening();
      await sub.cancel();
      expect(rxEngine.frameErrors, greaterThanOrEqualTo(1));
      expect(rxEngine.framesReceived, 0);
      expect(events.any((e) => e.errorMessage != null), isTrue);
    });

    test('decodes frames without RS parity when enable_rs is false', () async {
      config['enable_rs'] = false;
      mockNative.demodOutput =
          MockSoundwaveNative.defaultFrame(withParity: false);
      final messages = <DecodedMessage>[];
      final sub = rxEngine.startListening().listen(messages.add);
      await settle();
      mockAudio.pushMockChunk(Float64List(samplesFor(7)));
      await settle();
      rxEngine.stopListening();
      await sub.cancel();
      expect(messages, hasLength(1));
      expect(messages[0].rawBytes, [1, 2, 3]);
    });

    test('CSS mode waits for a CSS-sized frame', () async {
      config['modulation'] = 0;
      final messages = <DecodedMessage>[];
      final sub = rxEngine.startListening().listen(messages.add);
      await settle();
      // An OFDM-sized amount of audio is far too short for a CSS frame.
      mockAudio.pushMockChunk(Float64List(5000));
      await settle();
      expect(messages, isEmpty);
      mockAudio.pushMockChunk(Float64List(samplesFor(39)));
      await settle();
      rxEngine.stopListening();
      await sub.cancel();
      expect(messages, hasLength(1));
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
