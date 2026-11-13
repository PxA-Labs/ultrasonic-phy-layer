// ARQ state machine tests (#100) over a simulated half-duplex lossy channel.
// Virtual time (fake_async) and seeded RNGs make every run deterministic.

import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/link_receiver.dart';

const senderId = 0x1111, receiverId = 0x2222;
const airtime = Duration(milliseconds: 100);
const ackAirtime = Duration(milliseconds: 40);

/// Sender <-> receiver over a channel that loses DATA frames with
/// probability [dataLoss] and replies with probability [replyLoss]. A lost
/// DATA frame is "detected but CRC failed" at the receiver when [nackOnLoss].
class SimChannel {
  final FakeAsync async;
  final Random rnd;
  final double dataLoss;
  final double replyLoss;
  final bool nackOnLoss;
  final bool arqAtReceiver;

  /// Optional script: decides per DATA transmission (0-based) whether it is
  /// lost; overrides [dataLoss].
  final bool Function(int n)? dropData;

  late final ArqSender sender;
  final LinkReceiver receiver = LinkReceiver(nodeId: receiverId);
  final List<LinkMessage> delivered = [];
  final List<Duration> dataSentAt = [];
  final List<LinkFrame> repliesSent = [];
  final DateTime t0 = DateTime(2026, 1, 1);

  SimChannel(
    this.async, {
    int seed = 1,
    this.dataLoss = 0,
    this.replyLoss = 0,
    this.nackOnLoss = false,
    this.arqAtReceiver = true,
    this.dropData,
  }) : rnd = Random(seed) {
    sender = ArqSender(
      nodeId: senderId,
      transmit: _transmit,
      responseAllowance: () => const Duration(milliseconds: 60),
      random: Random(seed + 1),
    );
  }

  DateTime get now => t0.add(async.elapsed);

  Future<Duration> _transmit(Uint8List payload) async {
    final n = dataSentAt.length;
    dataSentAt.add(async.elapsed);
    final lost = dropData != null ? dropData!(n) : rnd.nextDouble() < dataLoss;
    final f = LinkFrame.decode(payload)!;
    Future<void>.delayed(airtime, () {
      if (lost) {
        final nack = receiver.onFrameError(now, arqEnabled: arqAtReceiver);
        if (nack != null && nackOnLoss) _reply(nack);
        return;
      }
      final out = receiver.handle(f, now, arqEnabled: arqAtReceiver);
      if (out.message != null) delivered.add(out.message!);
      if (out.reply != null) _reply(out.reply!);
    });
    return airtime;
  }

  void _reply(LinkFrame reply) {
    repliesSent.add(reply);
    final lost = rnd.nextDouble() < replyLoss;
    Future<void>.delayed(ackAirtime, () {
      if (!lost) sender.onControlFrame(LinkFrame.decode(reply.encode())!);
    });
  }
}

/// Runs [body] in virtual time and returns the outcome of its future.
({bool done, Object? error}) run(FakeAsync async, Future<void> Function() body,
    {Duration limit = const Duration(hours: 1)}) {
  var done = false;
  Object? error;
  body().then((_) {
    done = true;
  }, onError: (Object e) {
    error = e;
  });
  async.elapse(limit);
  return (done: done, error: error);
}

LinkMessage fileOf(int n, int seed) {
  final rnd = Random(seed);
  return LinkMessage.file(
      Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256))),
      fileName: 'f$seed.bin');
}

void main() {
  const arq = ArqConfig(
      enabled: true, maxRetries: 3, ackTimeout: Duration(milliseconds: 200));

  group('ArqConfig', () {
    test('reads settings from the config map with safe fallbacks', () {
      final c = ArqConfig.fromMap({
        'arq_enabled': true,
        'arq_max_retries': 5,
        'arq_ack_timeout_ms': 800,
      });
      expect(c.enabled, isTrue);
      expect(c.maxRetries, 5);
      expect(c.ackTimeout, const Duration(milliseconds: 800));
      final d = ArqConfig.fromMap(
          {'arq_max_retries': -1, 'arq_ack_timeout_ms': 99999});
      expect(d.enabled, isFalse);
      expect(d.maxRetries, 3);
      expect(d.ackTimeout, const Duration(milliseconds: 500));
    });

    test('exponential backoff is capped', () {
      const c = ArqConfig(
          ackTimeout: Duration(milliseconds: 500),
          maxBackoff: Duration(seconds: 3));
      expect(c.backoffFor(0), const Duration(milliseconds: 500));
      expect(c.backoffFor(1), const Duration(seconds: 1));
      expect(c.backoffFor(2), const Duration(seconds: 2));
      expect(c.backoffFor(3), const Duration(seconds: 3));
      expect(c.backoffFor(10), const Duration(seconds: 3));
    });
  });

  group('ArqSender state machine', () {
    test('send -> wait -> NACK -> retransmit -> ACK -> done', () {
      fakeAsync((async) {
        // First DATA transmission is corrupted; the receiver has a session
        // only after fragment 0, so lose fragment 1's first attempt.
        final ch = SimChannel(async, nackOnLoss: true, dropData: (n) => n == 1);
        final msg = LinkMessage.text('x' * 300); // 2 fragments
        final events = <TxTransferState>[];
        ch.sender.progress.listen((p) => events.add(p.state));
        final r = run(async, () => ch.sender.send(msg, arq));

        expect(r.error, isNull);
        expect(r.done, isTrue);
        expect(ch.dataSentAt, hasLength(3)); // frag0, frag1 (lost), frag1
        expect(ch.repliesSent.map((f) => f.type).toList(), [
          LinkFrameType.ack,
          LinkFrameType.nack,
          LinkFrameType.ack,
        ]);
        expect(ch.repliesSent[1].index, 1);
        // The NACK triggers the retransmission well before the ACK timeout.
        final gap = ch.dataSentAt[2] - ch.dataSentAt[1];
        expect(
            gap,
            lessThan(
                airtime + const Duration(milliseconds: 60) + arq.ackTimeout));
        expect(ch.delivered.single.text, 'x' * 300);
        expect(ch.sender.retransmissions, 1);
        expect(events, contains(TxTransferState.retrying));
        expect(events.last, TxTransferState.completed);
      });
    });

    test('timeout without NACK retransmits with exponential backoff', () {
      fakeAsync((async) {
        final ch = SimChannel(async, dropData: (n) => n < 3);
        final r = run(async, () => ch.sender.send(LinkMessage.text('hi'), arq));
        expect(r.done, isTrue);
        expect(ch.dataSentAt, hasLength(4));
        final gaps = [
          for (var i = 1; i < 4; i++) ch.dataSentAt[i] - ch.dataSentAt[i - 1],
        ];
        // airtime + allowance + 200 ms * 2^attempt + up to 10 % jitter
        const base = Duration(milliseconds: 160);
        for (var a = 0; a < 3; a++) {
          final backoff = Duration(milliseconds: 200 * (1 << a));
          expect(gaps[a], greaterThanOrEqualTo(base + backoff));
          expect(gaps[a],
              lessThan(base + backoff + const Duration(milliseconds: 21)));
        }
        expect(ch.delivered, hasLength(1));
      });
    });

    test('max retries exhaustion raises TxMaxRetriesError', () {
      fakeAsync((async) {
        final ch = SimChannel(async, dataLoss: 1.0);
        final states = <TxTransferState>[];
        ch.sender.progress.listen((p) => states.add(p.state));
        final r = run(async, () => ch.sender.send(LinkMessage.text('hi'), arq));
        expect(r.done, isFalse);
        expect(r.error, isA<TxMaxRetriesError>());
        final e = r.error as TxMaxRetriesError;
        expect(e.attempts, 4);
        expect(e.fragmentIndex, 0);
        expect(ch.dataSentAt, hasLength(4)); // 1 + maxRetries
        expect(states.last, TxTransferState.failed);
      });
    });

    test('duplicate and stale ACKs do not double-advance', () {
      fakeAsync((async) {
        final frames = <LinkFrame>[];
        late ArqSender sender;
        sender = ArqSender(
          nodeId: senderId,
          random: Random(3),
          transmit: (p) async {
            final f = LinkFrame.decode(p)!;
            frames.add(f);
            final ack = LinkFrame.ack(
                src: receiverId, dst: senderId, msgId: f.msgId, index: f.index);
            // Every ACK arrives three times; the previous fragment's ACK
            // arrives again too (late duplicate).
            Future<void>.delayed(airtime, () {
              sender.onControlFrame(ack);
              sender.onControlFrame(ack);
              sender.onControlFrame(ack);
              if (f.index > 0) {
                sender.onControlFrame(LinkFrame.ack(
                    src: receiverId,
                    dst: senderId,
                    msgId: f.msgId,
                    index: f.index - 1));
              }
            });
            return airtime;
          },
        );
        final msg = LinkMessage.text('y' * 1000); // 5 fragments
        final r = run(async, () => sender.send(msg, arq));
        expect(r.done, isTrue);
        expect(frames.map((f) => f.index).toList(), [0, 1, 2, 3, 4]);
        expect(sender.retransmissions, 0);
        expect(sender.duplicateReplies, greaterThanOrEqualTo(2 * 5 + 4));
      });
    });

    test('ACKs for another node or message are ignored', () {
      fakeAsync((async) {
        late ArqSender sender;
        var sent = 0;
        sender = ArqSender(
          nodeId: senderId,
          random: Random(4),
          transmit: (p) async {
            sent++;
            final f = LinkFrame.decode(p)!;
            Future<void>.delayed(airtime, () {
              sender.onControlFrame(LinkFrame.ack(
                  src: receiverId, dst: 0x9999, msgId: f.msgId, index: 0));
              sender.onControlFrame(LinkFrame.ack(
                  src: receiverId,
                  dst: senderId,
                  msgId: (f.msgId + 1) & 0xFFFF,
                  index: 0));
            });
            return airtime;
          },
        );
        final r = run(async, () => sender.send(LinkMessage.text('z'), arq));
        expect(r.error, isA<TxMaxRetriesError>());
        expect(sent, 4);
      });
    });

    test('ARQ off: fragments are broadcast once, paced by airtime', () {
      fakeAsync((async) {
        final ch = SimChannel(async, arqAtReceiver: false);
        final msg = fileOf(2000, 1);
        final r = run(
            async, () => ch.sender.send(msg, const ArqConfig(enabled: false)));
        expect(r.done, isTrue);
        final n = PayloadFragmenter.fragmentCount(
            msg.encode().length, LinkFrame.maxChunk);
        expect(ch.dataSentAt, hasLength(n));
        for (var i = 1; i < n; i++) {
          expect(ch.dataSentAt[i] - ch.dataSentAt[i - 1], airtime);
        }
        expect(ch.repliesSent, isEmpty);
        expect(ch.delivered.single.content, msg.content);
      });
    });

    test('receiver with ARQ off never replies, even if asked', () {
      fakeAsync((async) {
        final ch = SimChannel(async, arqAtReceiver: false);
        final r = run(async, () => ch.sender.send(LinkMessage.text('a'), arq));
        expect(r.error, isA<TxMaxRetriesError>());
        expect(ch.repliesSent, isEmpty);
        expect(ch.delivered, hasLength(1)); // still received (once)
      });
    });

    test('cancel aborts the transfer', () {
      fakeAsync((async) {
        final ch = SimChannel(async, dropData: (n) => n == 0);
        Object? error;
        ch.sender.send(fileOf(1000, 2), arq).then((_) {}, onError: (Object e) {
          error = e;
        });
        async.elapse(const Duration(milliseconds: 150));
        ch.sender.cancel();
        async.flushMicrotasks();
        expect(error, isA<TransferCancelledError>());
        final sent = ch.dataSentAt.length;
        async.elapse(const Duration(minutes: 1));
        expect(ch.dataSentAt.length, sent);
        // The sender is usable again afterwards.
        final r = run(async, () => ch.sender.send(LinkMessage.text('ok'), arq));
        expect(r.done, isTrue);
        expect(ch.delivered.single.text, 'ok');
      });
    });

    test('concurrent sends are serialised', () {
      fakeAsync((async) {
        final ch = SimChannel(async);
        var finished = 0;
        for (final t in ['one', 'two', 'three']) {
          ch.sender.send(LinkMessage.text(t), arq).then((_) => finished++);
        }
        async.elapse(const Duration(minutes: 1));
        expect(finished, 3);
        expect(
            ch.delivered.map((m) => m.text).toList(), ['one', 'two', 'three']);
      });
    });
  });

  group('ARQ over a lossy channel (seeded)', () {
    for (final seed in [1, 2, 3]) {
      test(
          '30 % DATA + 30 % ACK loss: multi-fragment file arrives intact '
          '(seed $seed)', () {
        fakeAsync((async) {
          final ch = SimChannel(async,
              seed: seed, dataLoss: 0.3, replyLoss: 0.3, nackOnLoss: true);
          final msg = fileOf(3000, seed); // 15 fragments
          final r = run(
              async,
              () => ch.sender.send(
                  msg,
                  const ArqConfig(
                      enabled: true,
                      maxRetries: 16,
                      ackTimeout: Duration(milliseconds: 200))));
          expect(r.error, isNull);
          expect(r.done, isTrue);
          expect(ch.delivered, hasLength(1)); // exactly once
          expect(ch.delivered.single.content, msg.content);
          expect(ch.sender.retransmissions, greaterThan(0));
        });
      });
    }

    test('delivery rate improves by > 20 % with ARQ at 40 % frame loss', () {
      // Frame-loss model only (no PHY): the acoustic SNR -> FER mapping is
      // covered by the native tests; this checks the protocol's gain.
      int deliveredOutOf100(bool withArq) {
        var ok = 0;
        fakeAsync((async) {
          final ch = SimChannel(async,
              seed: 100, dataLoss: 0.4, replyLoss: 0.4, nackOnLoss: true);
          for (var i = 0; i < 100; i++) {
            run(
                async,
                () => ch.sender.send(LinkMessage.text('message $i'),
                    withArq ? arq : const ArqConfig(enabled: false)),
                limit: const Duration(minutes: 1));
          }
          ok = ch.delivered.length;
        });
        return ok;
      }

      final without = deliveredOutOf100(false);
      final withArq = deliveredOutOf100(true);
      expect(without, inInclusiveRange(40, 80)); // ~60 expected
      expect(withArq, greaterThan(without * 1.2));
      expect(withArq, greaterThanOrEqualTo(90)); // 1 - 0.4^4 = 97.4 %
    });
  });

  group('LinkReceiver', () {
    final t0 = DateTime(2026, 1, 1);

    test('ignores its own echo and replies addressed elsewhere', () {
      final rx = LinkReceiver(nodeId: 5);
      final own = LinkFrame.data(
          src: 5,
          msgId: 1,
          index: 0,
          count: 1,
          chunk: Uint8List(3),
          ackRequested: true);
      final o1 = rx.handle(own, t0, arqEnabled: true);
      expect([o1.message, o1.reply, o1.control, o1.progress],
          everyElement(isNull));
      final other = LinkFrame.ack(src: 6, dst: 7, msgId: 1, index: 0);
      expect(rx.handle(other, t0, arqEnabled: true).control, isNull);
      final mine = LinkFrame.ack(src: 6, dst: 5, msgId: 1, index: 0);
      expect(rx.handle(mine, t0, arqEnabled: true).control, same(mine));
    });

    test('debounces identical replies but re-ACKs genuine retransmissions', () {
      final rx = LinkReceiver(nodeId: 5);
      final f = PayloadFragmenter(maxChunk: 4).fragment(
          LinkMessage.text('abcdefgh'),
          src: 6,
          msgId: 1,
          ackRequested: true)[0];
      expect(rx.handle(f, t0, arqEnabled: true).reply, isNotNull);
      expect(
          rx
              .handle(f, t0.add(const Duration(milliseconds: 50)),
                  arqEnabled: true)
              .reply,
          isNull);
      expect(
          rx
              .handle(f, t0.add(const Duration(seconds: 1)), arqEnabled: true)
              .reply,
          isNotNull);
    });

    test('NACKs only when exactly one ARQ transfer is in progress', () {
      final rx = LinkReceiver(nodeId: 5);
      expect(rx.onFrameError(t0, arqEnabled: true), isNull); // no context
      List<LinkFrame> frags(int src) =>
          PayloadFragmenter(maxChunk: 4).fragment(LinkMessage.text('abcdefgh'),
              src: src, msgId: 1, ackRequested: true);
      rx.handle(frags(6)[0], t0, arqEnabled: true);
      rx.handle(frags(6)[1], t0, arqEnabled: true);
      expect(rx.onFrameError(t0, arqEnabled: false), isNull);
      final nack = rx.onFrameError(t0, arqEnabled: true)!;
      expect([nack.type, nack.dst, nack.msgId, nack.index],
          [LinkFrameType.nack, 6, 1, 2]);
      rx.handle(frags(7)[0], t0, arqEnabled: true);
      expect(
          rx.onFrameError(t0.add(const Duration(seconds: 1)), arqEnabled: true),
          isNull); // ambiguous: two senders
    });
  });
}
