// Unit tests for link-layer frames and message envelopes (#89, #100).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/link_frame.dart';

void main() {
  group('Crc32', () {
    test('matches the IEEE check value', () {
      expect(Crc32.compute(ascii.encode('123456789')), 0xCBF43926);
      expect(Crc32.compute(const []), 0);
    });
  });

  group('LinkFrame', () {
    test('DATA round-trips and fits one PHY frame', () {
      final chunk =
          Uint8List.fromList(List.generate(LinkFrame.maxChunk, (i) => i));
      final f = LinkFrame.data(
          src: 0xBEEF,
          msgId: 0x1234,
          index: 6,
          count: 7,
          chunk: chunk,
          ackRequested: true);
      final bytes = f.encode();
      expect(bytes.length, FrameCodec.maxPayload);
      expect(bytes[0], LinkFrame.magic);
      final d = LinkFrame.decode(bytes)!;
      expect(d.type, LinkFrameType.data);
      expect(d.src, 0xBEEF);
      expect(d.msgId, 0x1234);
      expect(d.index, 6);
      expect(d.count, 7);
      expect(d.ackRequested, isTrue);
      expect(d.chunk, chunk);
    });

    test('ACK and NACK round-trip', () {
      final ack = LinkFrame.decode(
          LinkFrame.ack(src: 1, dst: 2, msgId: 3, index: 4).encode())!;
      expect([ack.type, ack.src, ack.dst, ack.msgId, ack.index],
          [LinkFrameType.ack, 1, 2, 3, 4]);
      final nack = LinkFrame.decode(
          LinkFrame.nack(src: 9, dst: 8, msgId: 7, index: 6).encode())!;
      expect(nack.type, LinkFrameType.nack);
      expect(nack.reason, NackReason.crcFailure);
      expect(nack.dst, 8);
    });

    test('legacy UTF-8 text is never mistaken for a link frame', () {
      for (final s in ['hello', 'ü€😀', 'ú']) {
        expect(LinkFrame.isLinkPayload(Uint8List.fromList(utf8.encode(s))),
            isFalse);
      }
    });

    test('rejects malformed frames', () {
      final good = LinkFrame.data(
              src: 1, msgId: 1, index: 0, count: 1, chunk: Uint8List(5))
          .encode();
      expect(LinkFrame.decode(Uint8List(0)), isNull);
      expect(LinkFrame.decode(good.sublist(0, 10)), isNull); // short header
      expect(LinkFrame.decode(good.sublist(0, 11)), isNull); // empty chunk
      expect(LinkFrame.decode(Uint8List.fromList([...good]..[1] = 9)), isNull);
      // index >= count
      expect(LinkFrame.decode(Uint8List.fromList([...good]..[7] = 1)), isNull);
      // count == 0
      expect(LinkFrame.decode(Uint8List.fromList([...good]..[9] = 0)), isNull);
      // ACK with trailing bytes
      final ack = LinkFrame.ack(src: 1, dst: 2, msgId: 3, index: 4).encode();
      expect(LinkFrame.decode(Uint8List.fromList([...ack, 0])), isNull);
      expect(
          () => LinkFrame.data(
              src: 1, msgId: 1, index: 0, count: 1, chunk: Uint8List(0)),
          throwsArgumentError);
      expect(() => LinkFrame.ack(src: 0x10000, dst: 0, msgId: 0, index: 0),
          throwsArgumentError);
    });
  });

  group('LinkMessage envelope', () {
    test('text and file round-trip', () {
      final t = LinkMessage.decode(LinkMessage.text('héllo').encode());
      expect(t.kind, PayloadKind.text);
      expect(t.text, 'héllo');

      final data = Uint8List.fromList(List.generate(1000, (i) => i * 7));
      final f = LinkMessage.decode(LinkMessage.file(data,
              fileName: 'report.pdf', mimeType: 'application/pdf')
          .encode());
      expect(f.kind, PayloadKind.file);
      expect(f.fileName, 'report.pdf');
      expect(f.mimeType, 'application/pdf');
      expect(f.content, data);

      final empty = LinkMessage.decode(
          LinkMessage.file(Uint8List(0), fileName: '').encode());
      expect(empty.content, isEmpty);
      expect(empty.fileName, '');
    });

    test('detects corruption, truncation and bad lengths', () {
      final e =
          LinkMessage.file(Uint8List.fromList([1, 2, 3, 4]), fileName: 'a.bin')
              .encode();
      final flipped = Uint8List.fromList(e)..[e.length - 1] ^= 0x01;
      expect(() => LinkMessage.decode(flipped), throwsFormatException);
      expect(() => LinkMessage.decode(e.sublist(0, e.length - 1)),
          throwsFormatException);
      expect(() => LinkMessage.decode(Uint8List.fromList([...e, 0])),
          throwsFormatException);
      expect(() => LinkMessage.decode(Uint8List.fromList([...e]..[0] = 9)),
          throwsFormatException);
      expect(() => LinkMessage.decode(Uint8List(4)), throwsFormatException);
    });

    test('enforces the 1 MB limit and bounds long names', () {
      expect(
          () => LinkMessage.file(Uint8List(LinkMessage.maxContentBytes + 1),
              fileName: 'x'),
          throwsArgumentError);
      final m = LinkMessage.file(Uint8List(1), fileName: '€' * 200);
      expect(utf8.encode(m.fileName!).length, lessThanOrEqualTo(255));
      expect(m.fileName, '€' * 85);
      expect(LinkMessage.decode(m.encode()).fileName, m.fileName);
    });
  });
}
