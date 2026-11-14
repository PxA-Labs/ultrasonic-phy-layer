// Unit tests for TxEngine.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/native/soundwave_native.dart';
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

  group('frame size follows the modem config', () {
    Map<String, dynamic> css(int sf, {double bandwidth = 2000.0}) => {
          'modulation': 0,
          'sample_rate': 44100,
          'sf': sf,
          'bandwidth': bandwidth,
          'enable_rs': true,
          'arq_enabled': false,
        };

    late MockSoundwaveNative native;
    TxEngine engine(Map<String, dynamic> cfg) {
      native = MockSoundwaveNative();
      return TxEngine(
        native: native,
        audio: MockAudioService(),
        configMap: cfg,
        useIsolates: false,
        nodeId: 7,
      );
    }

    /// Every frame handed to the modulator fits the TX budget and the FFI
    /// sample cap; returns their airtimes in seconds.
    List<double> checkFrames(Map<String, dynamic> cfg) {
      final g = FrameGeometry.fromConfig(cfg);
      final budget =
          g.txFrameSampleBudget(minPayload: LinkFrame.headerLength + 1);
      expect(native.modulatedFrames, isNotEmpty);
      final airtimes = <double>[];
      for (final f in native.modulatedFrames) {
        final n = g.samplesForFrameBytes(f.length);
        expect(n, lessThanOrEqualTo(budget));
        expect(n, lessThanOrEqualTo(SoundwaveNative.maxFrameSamples));
        airtimes.add(n / g.sampleRate);
      }
      return airtimes;
    }

    test('OFDM keeps full-size frames and legacy single-frame text', () async {
      final cfg = <String, dynamic>{
        'modulation': 1,
        'sample_rate': 44100,
        'enable_rs': true,
      };
      final tx = engine(cfg);
      expect(tx.maxFramePayload, FrameCodec.maxPayload);
      expect(tx.linkChunkBytes, LinkFrame.maxChunk);
      await tx.sendMessage('x' * FrameCodec.maxPayload);
      expect(native.modulatedFrames, hasLength(1)); // legacy raw frame
    });

    test('SF10 / 2 kHz: a long message is fragmented into frames that fit',
        () async {
      final cfg = css(10);
      final tx = engine(cfg);
      // A full 219-byte payload would need ~110 s (> the FFI sample cap).
      final g = FrameGeometry.fromConfig(cfg);
      expect(
          g.samplesForFrameBytes(FrameCodec.crcLength +
              FrameCodec.maxPayload +
              FrameCodec.parityLength),
          greaterThan(SoundwaveNative.maxFrameSamples));
      expect(tx.maxFramePayload, lessThan(FrameCodec.maxPayload));
      expect(tx.frameLimitError, isNull);

      final text = List.generate(500, (i) => 'abcdefghij'[i % 10]).join();
      await tx.sendMessage(text);
      final airtimes = checkFrames(cfg);
      expect(airtimes.length, greaterThan(text.length ~/ tx.linkChunkBytes));
      // Twice the shortest link frame (~25 s) bounds every frame.
      for (final t in airtimes) {
        expect(t, lessThan(55));
      }
    });

    test('SF10 / 2 kHz: short legacy text that is too slow is fragmented',
        () async {
      final cfg = css(10);
      final tx = engine(cfg);
      final text = 'y' * (tx.maxFramePayload + 1); // fits 219, not the budget
      await tx.sendMessage(text);
      expect(native.modulatedFrames.length, greaterThan(1));
      checkFrames(cfg);
      // Link frames, not a raw legacy frame.
      final first = native.modulatedFrames.first;
      final payload = first.sublist(
          FrameCodec.crcLength, first.length - FrameCodec.parityLength);
      expect(LinkFrame.isLinkPayload(payload), isTrue);
    });

    test('SF8 / 2 kHz frames are capped near 15 s of airtime', () async {
      final cfg = css(8);
      final tx = engine(cfg);
      await tx.sendBinary(Uint8List(600), fileName: 'f.bin');
      for (final t in checkFrames(cfg)) {
        expect(t, lessThanOrEqualTo(FrameGeometry.targetFrameAirtimeSeconds));
      }
    });

    test('a config that cannot fit any frame is rejected clearly', () async {
      final cfg = css(10, bandwidth: 300.0); // ~3.4 s per chirp
      final tx = engine(cfg);
      expect(tx.frameLimitError, contains('too slow'));
      expect(() => tx.linkChunkBytes, throwsA(isA<FrameTooLongError>()));
      await expectLater(
          tx.sendMessage('hi'), throwsA(isA<FrameTooLongError>()));
      await expectLater(
          tx.sendBinary(Uint8List(10)), throwsA(isA<FrameTooLongError>()));
      expect(native.modulatedFrames, isEmpty);
    });
  });
}
