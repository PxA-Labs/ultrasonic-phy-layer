// TxEngine / RxEngine link-layer integration with the mock native layer
// (#89, #100). Real-DSP end-to-end transfer: test/native/loopback_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/link_receiver.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/engine/tx_queue.dart';
import 'package:soundwave/native/bindings.dart';

import 'mock_native.dart';

/// Records every PHY frame handed to the modulator.
class CapturingNative extends MockSoundwaveNative {
  final List<Uint8List> frames = [];
  void Function(Uint8List frame)? onFrame;

  @override
  Float32List cssModulate(Uint8List bits, Pointer<SwConfig> config) {
    frames.add(Uint8List.fromList(bits));
    onFrame?.call(bits);
    return super.cssModulate(bits, config);
  }

  /// The link payload inside a captured PHY frame (CRC + payload + parity).
  static Uint8List payloadOf(Uint8List frame) =>
      Uint8List.sublistView(frame, 4, frame.length - 32);
}

/// PHY frame as the mock codec expects it: byte-sum "CRC", dummy parity.
Uint8List mockFrame(Uint8List payload) {
  final sum = payload.fold<int>(0, (a, b) => a + b);
  return Uint8List.fromList([
    sum & 0xFF,
    (sum >> 8) & 0xFF,
    (sum >> 16) & 0xFF,
    (sum >> 24) & 0xFF,
    ...payload,
    ...List.filled(32, 0xAA),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TxEngine link layer', () {
    late CapturingNative native;
    late MockAudioService audio;
    late Map<String, dynamic> config;
    late TxEngine tx;

    // Engines must be created inside fakeAsync zones when used there: futures
    // created in another zone schedule their callbacks on real microtasks.
    TxEngine build() => TxEngine(
        native: native,
        audio: audio,
        configMap: config,
        useIsolates: false,
        nodeId: 0x0A0A);

    setUp(() {
      native = CapturingNative();
      audio = MockAudioService();
      config = {'modulation': 0, 'sample_rate': 44100};
      tx = build();
    });

    test('short text without ARQ stays a single legacy frame', () async {
      await tx.sendMessage('hello');
      expect(native.frames, hasLength(1));
      expect(utf8.decode(CapturingNative.payloadOf(native.frames.single)),
          'hello');
    });

    test('text longer than one frame is fragmented and reassembles', () async {
      final text = List.generate(600, (i) => 'abc'[i % 3]).join();
      final progress = <TxTransferProgress>[];
      final sub = tx.transfers.listen(progress.add);
      await tx.sendMessage(text);
      await Future<void>.delayed(Duration.zero); // deliver broadcast events
      await sub.cancel();

      final frames = [
        for (final f in native.frames)
          LinkFrame.decode(CapturingNative.payloadOf(f))!,
      ];
      // CSS SF8 / 2 kHz: chunks are sized for ~15 s frames, not 208 bytes.
      expect(tx.linkChunkBytes, lessThan(LinkFrame.maxChunk));
      final count = PayloadFragmenter.fragmentCount(
          LinkMessage.text(text).encode().length, tx.linkChunkBytes);
      expect(count, greaterThan(3));
      expect(frames, hasLength(count));
      expect(frames.every((f) => f.src == 0x0A0A && !f.ackRequested), isTrue);
      final rx = LinkReceiver(nodeId: 1);
      final out = [
        for (final f in frames.reversed)
          rx.handle(f, DateTime.now(), arqEnabled: false),
      ];
      expect(out.last.message!.text, text);
      expect(progress.last.state, TxTransferState.completed);
      expect(progress.last.fragmentsDone, count);
    });

    test('sendBinary with ARQ waits for each ACK', () {
      fakeAsync((async) {
        tx = build();
        config['arq_enabled'] = true;
        native.onFrame = (frame) {
          final f = LinkFrame.decode(CapturingNative.payloadOf(frame))!;
          Timer(const Duration(milliseconds: 5), () {
            tx.onControlFrame(LinkFrame.ack(
                src: 0x0B0B, dst: 0x0A0A, msgId: f.msgId, index: f.index));
          });
        };
        var done = false;
        tx
            .sendBinary(Uint8List(1000), fileName: 'z.bin')
            .then((_) => done = true);
        async.elapse(const Duration(minutes: 5));
        expect(done, isTrue);
        final envelope =
            LinkMessage.file(Uint8List(1000), fileName: 'z.bin').encode();
        final count =
            PayloadFragmenter.fragmentCount(envelope.length, tx.linkChunkBytes);
        expect(native.frames, hasLength(count));
        expect(tx.retransmissions, 0);
        final f0 =
            LinkFrame.decode(CapturingNative.payloadOf(native.frames[0]))!;
        expect(f0.ackRequested, isTrue);
      });
    });

    test('TxQueue.enqueueFile reports TxMaxRetriesError', () {
      fakeAsync((async) {
        tx = build();
        config
          ..['arq_enabled'] = true
          ..['arq_max_retries'] = 1;
        final queue = TxQueue(txEngine: tx);
        Object? error;
        queue
            .enqueueFile(Uint8List(10),
                fileName: 'a.bin', mimeType: 'application/octet-stream')
            .then((_) {}, onError: (Object e) {
          error = e;
        });
        async.elapse(const Duration(minutes: 10));
        expect(error, isA<TxMaxRetriesError>());
        expect(native.frames, hasLength(2));
      });
    });
  });

  group('RxEngine link layer', () {
    late MockSoundwaveNative native;
    late MockAudioService audio;
    late Map<String, dynamic> config;
    late RxEngine rx;

    setUp(() {
      native = MockSoundwaveNative()..framesToDetect = 1;
      audio = MockAudioService();
      config = {'modulation': 1, 'sample_rate': 44100, 'arq_enabled': true};
      rx = RxEngine(
          native: native,
          audio: audio,
          configMap: config,
          useIsolates: false,
          nodeId: 0x0B0B);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('decodes a single-fragment file from audio and ACKs it', () async {
      final envelope = LinkMessage.file(Uint8List.fromList([1, 2, 3]),
              fileName: 'a.bin', mimeType: 'application/x-test')
          .encode();
      final payload = LinkFrame.data(
              src: 0x0A0A,
              msgId: 5,
              index: 0,
              count: 1,
              chunk: envelope,
              ackRequested: true)
          .encode();
      final frame = mockFrame(payload);
      native.demodOutput = frame;

      final files = <ReceivedFile>[];
      final replies = <LinkFrame>[];
      final texts = <DecodedMessage>[];
      final subs = [
        rx.files.listen(files.add),
        rx.controlReplies.listen(replies.add),
        rx.startListening().listen(texts.add),
      ];
      await settle();
      final g = FrameGeometry.fromConfig(config);
      audio.pushMockChunk(Float64List(
          g.searchWindowSamples + g.samplesForFrameBytes(frame.length)));
      await settle();
      rx.stopListening();
      for (final s in subs) {
        await s.cancel();
      }

      expect(texts, isEmpty);
      expect(files, hasLength(1));
      expect(files.single.data, [1, 2, 3]);
      expect(files.single.fileName, 'a.bin');
      expect(files.single.mimeType, 'application/x-test');
      expect(files.single.src, 0x0A0A);
      expect(replies, hasLength(1));
      expect(replies.single.type, LinkFrameType.ack);
      expect(replies.single.dst, 0x0A0A);
      expect(replies.single.src, 0x0B0B);
    });

    test('routes text, control frames and own echoes', () async {
      final texts = <String>[];
      final control = <LinkFrame>[];
      final replies = <LinkFrame>[];
      final subs = [
        rx.messages.listen((m) => texts.add(m.text)),
        rx.controlFrames.listen(control.add),
        rx.controlReplies.listen(replies.add),
      ];
      final frames = [
        for (final f in [
          LinkFrame.data(
              src: 0x0B0B, // our own echo
              msgId: 1,
              index: 0,
              count: 1,
              chunk: LinkMessage.text('echo').encode(),
              ackRequested: true),
          LinkFrame.ack(src: 0x0A0A, dst: 0x0B0B, msgId: 9, index: 0),
          LinkFrame.ack(src: 0x0A0A, dst: 0x0C0C, msgId: 9, index: 0),
          LinkFrame.data(
              src: 0x0A0A,
              msgId: 2,
              index: 0,
              count: 1,
              chunk: LinkMessage.text('hello link').encode()),
        ])
          f.encode(),
      ];
      for (final p in frames) {
        rx.handleLinkPayload(p);
      }
      rx.handleLinkPayload(Uint8List.fromList([LinkFrame.magic, 99]));
      await settle();
      for (final s in subs) {
        await s.cancel();
      }
      expect(texts, ['hello link']);
      expect(control.map((f) => f.msgId), [9]);
      expect(replies, isEmpty); // echo ignored; data 2 did not ask for ACK
    });

    test('an abandoned transfer is reported as failed', () async {
      final events = <RxTransferProgress>[];
      final sub = rx.transfers.listen(events.add);
      final frag = LinkFrame.data(
          src: 0x0A0A,
          msgId: 3,
          index: 0,
          count: 2,
          chunk: Uint8List.fromList([1]));
      rx.handleLinkPayload(frag.encode(), now: DateTime(2000));
      await settle();
      await sub.cancel();
      expect(events.first.state, RxTransferState.receiving);
      expect(events.last.state, RxTransferState.failed);
      expect(events.last.error, contains('timed out'));
      expect(rx.reassemblyTimeout, greaterThan(const Duration(seconds: 30)));
    });
  });
}
