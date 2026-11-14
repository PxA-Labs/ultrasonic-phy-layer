// File-transfer timing and end-of-transfer notices (#89), plus the 100 KB
// end-to-end binary transfer the issue asks for: TxEngine -> link frames ->
// lossy simulated channel -> RxEngine, with ARQ ACKs flowing back.

import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/transfer_notice.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/native/bindings.dart';

import 'link_engines_test.dart' show CapturingNative;
import 'mock_native.dart';

/// [CapturingNative] for OFDM frames as well as CSS.
class CapturingOfdmNative extends CapturingNative {
  @override
  Float32List ofdmModulate(Uint8List bits, Pointer<SwConfig> config) {
    frames.add(Uint8List.fromList(bits));
    onFrame?.call(bits);
    return super.ofdmModulate(bits, config);
  }
}

List<LinkFrame> fragmentsOf(int bytes, {int chunk = 100, int msgId = 7}) =>
    PayloadFragmenter(maxChunk: chunk).fragment(
      LinkMessage.file(Uint8List(bytes), fileName: 'f.bin'),
      src: 0x0A0A,
      msgId: msgId,
      ackRequested: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatTransferDuration', () {
    test('seconds with one decimal, truncated below a minute', () {
      expect(formatTransferDuration(Duration.zero), '0.0 s');
      expect(
          formatTransferDuration(const Duration(milliseconds: 420)), '0.4 s');
      expect(
          formatTransferDuration(const Duration(milliseconds: 8650)), '8.6 s');
      expect(formatTransferDuration(const Duration(milliseconds: 59999)),
          '59.9 s');
    });

    test('minutes and hours', () {
      expect(formatTransferDuration(const Duration(seconds: 60)), '1 min 00 s');
      expect(formatTransferDuration(const Duration(seconds: 65)), '1 min 05 s');
      expect(formatTransferDuration(const Duration(minutes: 59, seconds: 59)),
          '59 min 59 s');
      expect(formatTransferDuration(const Duration(hours: 1, minutes: 2)),
          '1 h 02 min');
    });
  });

  test('formatBitRate picks a unit', () {
    expect(formatBitRate(420.4), '420 bit/s');
    expect(formatBitRate(11500), '11.5 kbit/s');
    expect(formatBitRate(1.2e6), '1.20 Mbit/s');
  });

  group('TransferNotice', () {
    test('received: name, size, time and throughput', () {
      const n = TransferNotice(
        direction: TransferDirection.received,
        fileName: 'photo.png',
        bytes: 12800,
        duration: Duration(seconds: 8),
      );
      expect(n.bitsPerSecond, closeTo(12800, 1e-9));
      expect(
          n.message, 'Received "photo.png" (12.5 KB) in 8.0 s · 12.8 kbit/s');
    });

    test('sent with retransmissions', () {
      const n = TransferNotice(
        direction: TransferDirection.sent,
        fileName: 'a.bin',
        bytes: 100,
        duration: Duration(milliseconds: 2500),
        retransmissions: 1,
      );
      expect(n.message,
          'Sent "a.bin" (100 B) in 2.5 s · 320 bit/s · 1 retransmission');
      expect(
        const TransferNotice(
          direction: TransferDirection.sent,
          fileName: 'a.bin',
          bytes: 100,
          duration: Duration(seconds: 1),
          retransmissions: 3,
        ).message,
        endsWith('3 retransmissions'),
      );
    });

    test('no time or throughput when the duration is unknown or tiny', () {
      const zero = TransferNotice(
          direction: TransferDirection.received,
          fileName: 'x',
          bytes: 5,
          duration: Duration.zero);
      expect(zero.message, 'Received "x" (5 B)');
      const tiny = TransferNotice(
          direction: TransferDirection.received,
          fileName: 'x',
          bytes: 5,
          duration: Duration(milliseconds: 20));
      expect(tiny.bitsPerSecond, isNull);
      expect(tiny.message, 'Received "x" (5 B) in 0.0 s');
    });

    test('failures say why', () {
      expect(
        const TransferNotice(
          direction: TransferDirection.sent,
          fileName: 'a.bin',
          bytes: 1,
          duration: Duration(seconds: 12),
          ok: false,
          error: 'not acknowledged',
        ).message,
        'Sending "a.bin" failed after 12.0 s: not acknowledged',
      );
      expect(
        const TransferNotice(
          direction: TransferDirection.received,
          fileName: 'b.bin',
          bytes: 1,
          duration: Duration(seconds: 1),
          ok: false,
          error: 'disk full',
        ).message,
        'Received "b.bin" but could not save it: disk full',
      );
    });
  });

  group('PayloadReassembler.startedAt', () {
    final t0 = DateTime(2026, 11, 14, 12);

    test('dated by the first fragment\'s frame start, kept to completion', () {
      final frags = fragmentsOf(450);
      expect(frags.length, greaterThan(2));
      final r = PayloadReassembler();
      FragmentResult? last;
      for (var i = 0; i < frags.length; i++) {
        final arrival = t0.add(Duration(seconds: i + 1));
        last = r.add(frags[i], arrival,
            startedAt: arrival.subtract(const Duration(milliseconds: 900)));
      }
      expect(last!.status, FragmentStatus.completed);
      expect(last.startedAt, t0.add(const Duration(milliseconds: 100)));
    });

    test('out-of-order: the first fragment heard dates the session', () {
      final frags = fragmentsOf(450).reversed.toList();
      final r = PayloadReassembler();
      FragmentResult? last;
      for (var i = 0; i < frags.length; i++) {
        last = r.add(frags[i], t0.add(Duration(seconds: i)));
      }
      expect(last!.status, FragmentStatus.completed);
      expect(last.startedAt, t0); // defaults to the arrival time
    });

    test('incomplete results carry no start time', () {
      final frags = fragmentsOf(450);
      final r = PayloadReassembler();
      expect(r.add(frags[0], t0).startedAt, isNull);
    });
  });

  test('ArqSender reports elapsed time, including ACK waits', () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026));
      late ArqSender sender;
      sender = ArqSender(
        nodeId: 1,
        now: clock.now,
        transmit: (payload) async {
          final f = LinkFrame.decode(payload)!;
          // The peer ACKs 300 ms after a 200 ms frame.
          Timer(const Duration(milliseconds: 500), () {
            sender.onControlFrame(
                LinkFrame.ack(src: 2, dst: 1, msgId: f.msgId, index: f.index));
          });
          return const Duration(milliseconds: 200);
        },
      );
      final progress = <TxTransferProgress>[];
      sender.progress.listen(progress.add);
      sender.send(
        LinkMessage.file(Uint8List(450), fileName: 'f.bin'),
        const ArqConfig(enabled: true, ackTimeout: Duration(seconds: 2)),
        maxChunk: 100,
      );
      async.elapse(const Duration(minutes: 1));
      final done = progress.last;
      expect(done.state, TxTransferState.completed);
      expect(progress.first.elapsed, Duration.zero);
      // Every fragment completes when its ACK arrives, 500 ms after sending.
      expect(
          done.elapsed, const Duration(milliseconds: 500) * done.fragmentCount);
    });
  });

  group('RxEngine transfer time', () {
    late Map<String, dynamic> config;
    late RxEngine rx;

    setUp(() {
      config = {'modulation': 1, 'sample_rate': 44100};
      rx = RxEngine(
          native: MockSoundwaveNative(),
          audio: MockAudioService(),
          configMap: config,
          useIsolates: false,
          nodeId: 0x0B0B);
    });

    test('frameAirtime matches the frame geometry', () {
      final g = FrameGeometry.fromConfig(config);
      final bytes = FrameCodec.crcLength + 100 + FrameCodec.parityLength;
      expect(rx.frameAirtime(100).inMicroseconds,
          g.samplesForFrameBytes(bytes) * 1000000 ~/ 44100);
      config['enable_rs'] = false;
      expect(rx.frameAirtime(100), lessThan(rx.frameAirtime(132)));
    });

    test('runs from the first frame\'s start to reassembly', () async {
      final files = <ReceivedFile>[];
      final sub = rx.files.listen(files.add);
      final frags = fragmentsOf(450);
      final t0 = DateTime(2026, 11, 14, 12);
      late DateTime lastArrival;
      for (var i = 0; i < frags.length; i++) {
        lastArrival = t0.add(Duration(seconds: 3 * i));
        rx.handleLinkPayload(frags[i].encode(), now: lastArrival);
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(files, hasLength(1));
      final firstAirtime = rx.frameAirtime(frags.first.encode().length);
      expect(firstAirtime, greaterThan(Duration.zero));
      expect(
          files.single.transferTime, lastArrival.difference(t0) + firstAirtime);
    });
  });

  test('100 KB file transfer end-to-end with ARQ over a lossy channel', () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026, 11, 14));
      final txNative = CapturingOfdmNative();
      final config = <String, dynamic>{
        'modulation': 1, // OFDM: the largest frames, fewest fragments
        'sample_rate': 44100,
        'arq_enabled': true,
        'arq_max_retries': 3,
        'arq_ack_timeout_ms': 500,
      };
      final tx = TxEngine(
          native: txNative,
          audio: MockAudioService(),
          configMap: config,
          useIsolates: false,
          nodeId: 0x0A0A,
          clock: clock.now);
      final rx = RxEngine(
          native: MockSoundwaveNative(),
          audio: MockAudioService(),
          configMap: Map.of(config),
          useIsolates: false,
          nodeId: 0x0B0B,
          clock: clock.now);

      // Channel: each frame is decoded 20 ms after it is handed to the
      // modulator; every 9th data frame is lost once. ACKs go straight back.
      var dataFrames = 0;
      final lost = <String>{};
      final arrivals = <(DateTime, int)>[]; // (time, payload length)
      txNative.onFrame = (frame) {
        final payload = Uint8List.fromList(CapturingNative.payloadOf(frame));
        final f = LinkFrame.decode(payload)!;
        dataFrames++;
        final key = '${f.msgId}/${f.index}';
        if (dataFrames % 9 == 0 && lost.add(key)) return;
        Timer(const Duration(milliseconds: 20), () {
          arrivals.add((clock.now(), payload.length));
          rx.handleLinkPayload(payload);
        });
      };
      rx.controlReplies.listen((ack) {
        Timer(const Duration(milliseconds: 5), () => tx.onControlFrame(ack));
      });
      final files = <ReceivedFile>[];
      rx.files.listen(files.add);
      final progress = <TxTransferProgress>[];
      tx.transfers.listen(progress.add);

      final rnd = Random(89);
      final data = Uint8List.fromList(
          List.generate(100 * 1024, (_) => rnd.nextInt(256)));
      Object? error;
      var done = false;
      DateTime? doneAt;
      final started = clock.now();
      tx.sendBinary(data, fileName: 'payload.bin').then((_) {
        done = true;
        doneAt = clock.now();
      }, onError: (Object e) {
        error = e;
      });
      async.elapse(const Duration(hours: 2));

      expect(error, isNull);
      expect(done, isTrue);
      expect(files, hasLength(1));
      final got = files.single;
      expect(got.fileName, 'payload.bin');
      expect(got.data, data);

      final last = progress.last;
      expect(last.state, TxTransferState.completed);
      final count = last.fragmentCount;
      expect(count, greaterThan(400)); // 100 KB in ~219-byte OFDM frames
      expect(lost, isNotEmpty);
      expect(last.retransmissions, lost.length);
      expect(tx.retransmissions, lost.length);

      // Timing. TX: first fragment handed to the PHY until the last ACK.
      // RX: last arrival minus first arrival, plus the first frame's
      // airtime (it is decoded only once it has ended). The mock PHY plays
      // frames instantly, so the two are not comparable here.
      expect(last.elapsed, doneAt!.difference(started));
      // Each lost frame was retransmitted once, so every fragment arrived once.
      expect(arrivals, hasLength(count));
      expect(
        got.transferTime,
        arrivals.last.$1.difference(arrivals.first.$1) +
            rx.frameAirtime(arrivals.first.$2),
      );

      final notice = TransferNotice(
        direction: TransferDirection.sent,
        fileName: 'payload.bin',
        bytes: last.contentBytes,
        duration: last.elapsed,
        retransmissions: last.retransmissions,
      );
      expect(notice.message, startsWith('Sent "payload.bin" (100.0 KB) in '));
      expect(notice.message, contains('retransmission'));
    });
  });
}
