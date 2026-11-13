// Property tests for fragmentation and reassembly (#89): random sizes,
// reordering, duplicates, loss, interleaving and timeouts. Deterministic seeds.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/link_frame.dart';

Uint8List randomBytes(Random rnd, int n) =>
    Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));

/// Simulates the air: encode -> decode every frame, like the RX path does.
List<LinkFrame> overTheAir(List<LinkFrame> frames) =>
    [for (final f in frames) LinkFrame.decode(f.encode())!];

void main() {
  final t0 = DateTime(2026, 1, 1);

  group('PayloadFragmenter', () {
    test('fragment count and sizes', () {
      final msg = LinkMessage.file(Uint8List(1000), fileName: 'f.bin');
      final envelope = msg.encode().length;
      final frames =
          PayloadFragmenter(maxChunk: 100).fragment(msg, src: 1, msgId: 2);
      expect(frames.length, (envelope + 99) ~/ 100);
      expect(frames.every((f) => f.count == frames.length), isTrue);
      expect(frames.take(frames.length - 1).every((f) => f.chunk.length == 100),
          isTrue);
      for (final f in frames) {
        expect(f.encode().length, lessThanOrEqualTo(f.chunk.length + 11));
      }
      expect(() => PayloadFragmenter(maxChunk: 0), throwsArgumentError);
      expect(() => PayloadFragmenter(maxChunk: LinkFrame.maxChunk + 1),
          throwsArgumentError);
    });

    test('a 1 MB file fits the 16-bit fragment counter', () {
      final msg = LinkMessage.file(Uint8List(LinkMessage.maxContentBytes),
          fileName: 'big.bin');
      final frames = PayloadFragmenter().fragment(msg, src: 1, msgId: 1);
      expect(frames.length, lessThan(0x10000));
      final r = PayloadReassembler();
      FragmentResult? last;
      for (final f in frames) {
        last = r.add(f, t0);
      }
      expect(last!.status, FragmentStatus.completed);
      expect(last.message!.content.length, LinkMessage.maxContentBytes);
    });
  });

  group('PayloadReassembler properties', () {
    test('split -> shuffle -> duplicate -> reassemble == original', () {
      final rnd = Random(89);
      for (var trial = 0; trial < 200; trial++) {
        final size = trial < 5 ? trial : rnd.nextInt(trial.isEven ? 600 : 6000);
        final data = randomBytes(rnd, size);
        final chunk = 1 + rnd.nextInt(LinkFrame.maxChunk);
        final msg = trial.isEven
            ? LinkMessage.file(data, fileName: 'f$trial.bin')
            : LinkMessage.text(String.fromCharCodes(
                data.map((b) => 0x20 + b % 0x5F))); // printable ASCII
        final frames = overTheAir(PayloadFragmenter(maxChunk: chunk)
            .fragment(msg, src: 7, msgId: trial));

        // Every fragment 1-3 times, in random order.
        final arrivals = [
          for (final f in frames)
            for (var k = rnd.nextInt(3); k >= 0; k--) f,
        ]..shuffle(rnd);
        final r = PayloadReassembler();
        final completed = <LinkMessage>[];
        for (final f in arrivals) {
          final res = r.add(f, t0);
          if (res.message != null) completed.add(res.message!);
          expect(res.status, isNot(FragmentStatus.rejected));
        }
        expect(completed, hasLength(1), reason: 'trial $trial');
        expect(completed.single.content, msg.content, reason: 'trial $trial');
        expect(completed.single.kind, msg.kind);
        expect(completed.single.fileName, msg.fileName);
        expect(r.sessions, isEmpty);
      }
    });

    test('loss: never delivers an incomplete message; reports it on timeout',
        () {
      final rnd = Random(4242);
      for (var trial = 0; trial < 100; trial++) {
        final data = randomBytes(rnd, 300 + rnd.nextInt(3000));
        final frames = overTheAir(PayloadFragmenter(maxChunk: 64).fragment(
            LinkMessage.file(data, fileName: 'x'),
            src: 3,
            msgId: trial));
        final lost = rnd.nextInt(frames.length);
        final r = PayloadReassembler(timeout: const Duration(seconds: 5));
        for (final f in (List.of(frames)..removeAt(lost))..shuffle(rnd)) {
          expect(r.add(f, t0).message, isNull);
        }
        expect(r.expire(t0.add(const Duration(seconds: 4))), isEmpty);
        final failures = r.expire(t0.add(const Duration(seconds: 5)));
        expect(failures, hasLength(1));
        expect(failures.single.received, frames.length - 1);
        expect(failures.single.count, frames.length);
        expect(failures.single.reason, contains('timed out'));
        expect(r.sessions, isEmpty);
      }
    });

    test('a late lost fragment still completes before the timeout', () {
      final frames = PayloadFragmenter(maxChunk: 10).fragment(
          LinkMessage.text('the quick brown fox jumps'),
          src: 1,
          msgId: 1);
      final r = PayloadReassembler(timeout: const Duration(seconds: 5));
      for (final f in frames.skip(1)) {
        r.add(f, t0);
      }
      expect(r.nextDeadline, t0.add(const Duration(seconds: 5)));
      final res = r.add(frames.first, t0.add(const Duration(seconds: 4)));
      expect(res.status, FragmentStatus.completed);
      expect(res.message!.text, 'the quick brown fox jumps');
      expect(r.nextDeadline, isNull);
    });

    test('interleaved messages from several senders are kept apart', () {
      final rnd = Random(5);
      final msgs = <String, LinkMessage>{};
      final arrivals = <LinkFrame>[];
      for (var src = 1; src <= 3; src++) {
        for (var id = 0; id < 2; id++) {
          final m = LinkMessage.file(randomBytes(rnd, 500), fileName: '$src-$id');
          msgs['$src-$id'] = m;
          arrivals.addAll(
              PayloadFragmenter(maxChunk: 50).fragment(m, src: src, msgId: id));
        }
      }
      arrivals.shuffle(rnd);
      final r = PayloadReassembler();
      final got = <String, LinkMessage>{};
      for (final f in arrivals) {
        final m = r.add(f, t0).message;
        if (m != null) got['${f.src}-${f.msgId}'] = m;
      }
      expect(got.keys.toSet(), msgs.keys.toSet());
      for (final k in msgs.keys) {
        expect(got[k]!.content, msgs[k]!.content);
      }
    });

    test('duplicates after completion are reported, not re-delivered', () {
      final frames = PayloadFragmenter(maxChunk: 4)
          .fragment(LinkMessage.text('abcdefgh'), src: 1, msgId: 9);
      final r = PayloadReassembler();
      var delivered = 0;
      for (final f in [...frames, ...frames, frames.last]) {
        final res = r.add(f, t0);
        if (res.message != null) delivered++;
      }
      expect(delivered, 1);
      expect(r.add(frames.first, t0).status, FragmentStatus.duplicate);
      // ...but a new message with the same id is accepted once forgotten.
      final later = t0.add(const Duration(hours: 1));
      expect(r.add(frames.first, later).status, FragmentStatus.accepted);
    });

    test('limits: size cap, session cap, inconsistent count', () {
      final r = PayloadReassembler(maxEnvelopeBytes: 100, maxSessions: 2);
      LinkFrame frag(int src, int id, int idx, int count, int len) =>
          LinkFrame.data(
              src: src,
              msgId: id,
              index: idx,
              count: count,
              chunk: Uint8List(len)..fillRange(0, len, 1));

      expect(r.add(frag(1, 1, 0, 3, 60), t0).status, FragmentStatus.accepted);
      final big = r.add(frag(1, 1, 1, 3, 60), t0);
      expect(big.status, FragmentStatus.rejected);
      expect(r.sessions, isEmpty);
      expect(r.expire(t0).single.reason, contains('exceeds'));

      r.add(frag(1, 2, 0, 2, 1), t0);
      r.add(frag(2, 2, 0, 2, 1), t0.add(const Duration(seconds: 1)));
      r.add(frag(3, 2, 0, 2, 1), t0.add(const Duration(seconds: 2)));
      expect(r.sessions.map((s) => s.src).toSet(), {2, 3});
      expect(r.expire(t0).single.reason, contains('evicted'));

      r.add(frag(3, 2, 0, 5, 1), t0); // same id, different count
      expect(r.sessions.firstWhere((s) => s.src == 3).count, 5);
      expect(r.expire(t0).single.reason, contains('superseded'));
    });

    test('lowestMissing tracks the next fragment a stop-and-wait sender owes',
        () {
      final frames = PayloadFragmenter(maxChunk: 3)
          .fragment(LinkMessage.text('0123456789abc'), src: 1, msgId: 1);
      final r = PayloadReassembler();
      r.add(frames[0], t0);
      r.add(frames[2], t0);
      expect(r.sessions.single.lowestMissing, 1);
    });
  });
}
