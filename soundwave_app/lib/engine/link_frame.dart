// Link layer frames (#89, #100) carried inside PHY frame payloads.
//
// A PHY payload (see FrameCodec) is either legacy raw UTF-8 text or a link
// frame starting with [LinkFrame.magic]. 0xFA never occurs in UTF-8, so the
// two cannot be confused and old text-only receivers keep working.
//
//   DATA      0 magic | 1 type=1 | 2 flags | 3-4 src | 5-6 msgId
//             7-8 index | 9-10 count | 11.. chunk
//   ACK/NACK  0 magic | 1 type=2/3 | 2 reason | 3-4 src | 5-6 dst
//             7-8 msgId | 9-10 index
//
// Multi-byte fields are little-endian. Every link frame is already protected
// by the PHY CRC-32 (+ RS); the reassembled message carries its own CRC-32
// (see [LinkMessage]) so a mis-assembled message is never delivered.

import 'dart:convert';
import 'dart:typed_data';

import 'package:soundwave/engine/frame_codec.dart';

/// CRC-32 (IEEE 802.3, reflected, init/xorout 0xFFFFFFFF) in pure Dart, so the
/// link layer is testable without the native library.
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }

  static int compute(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

enum LinkFrameType { data, ack, nack }

/// Why a receiver sent a NACK.
class NackReason {
  /// A frame was detected but failed CRC / RS verification.
  static const int crcFailure = 1;
}

class LinkFrame {
  static const int magic = 0xFA;
  static const int headerLength = 11;

  /// Largest DATA chunk that still fits one PHY frame.
  static const int maxChunk = FrameCodec.maxPayload - headerLength;

  /// DATA flag: the sender runs ARQ and waits for an ACK per fragment.
  static const int flagAckRequested = 0x01;

  static const int _typeData = 1, _typeAck = 2, _typeNack = 3;

  final LinkFrameType type;
  final int src;
  final int msgId;
  final int index;

  /// DATA: number of fragments in the message. 0 for ACK/NACK.
  final int count;

  /// ACK/NACK: node the reply is addressed to. 0 for DATA.
  final int dst;

  /// DATA: flag bits. 0 for ACK/NACK.
  final int flags;

  /// NACK: [NackReason]. 0 otherwise.
  final int reason;

  /// DATA: fragment bytes. Empty for ACK/NACK.
  final Uint8List chunk;

  LinkFrame._({
    required this.type,
    required this.src,
    required this.msgId,
    required this.index,
    this.count = 0,
    this.dst = 0,
    this.flags = 0,
    this.reason = 0,
    Uint8List? chunk,
  }) : chunk = chunk ?? Uint8List(0) {
    for (final v in [src, msgId, index, count, dst]) {
      if (v < 0 || v > 0xFFFF) {
        throw ArgumentError.value(v, 'field', 'must fit in 16 bits');
      }
    }
  }

  factory LinkFrame.data({
    required int src,
    required int msgId,
    required int index,
    required int count,
    required Uint8List chunk,
    bool ackRequested = false,
  }) {
    if (count < 1 || index >= count) {
      throw ArgumentError('fragment index $index out of range 0..$count');
    }
    if (chunk.isEmpty || chunk.length > maxChunk) {
      throw ArgumentError.value(
          chunk.length, 'chunk.length', 'must be 1..$maxChunk');
    }
    return LinkFrame._(
      type: LinkFrameType.data,
      src: src,
      msgId: msgId,
      index: index,
      count: count,
      flags: ackRequested ? flagAckRequested : 0,
      chunk: chunk,
    );
  }

  factory LinkFrame.ack({
    required int src,
    required int dst,
    required int msgId,
    required int index,
  }) =>
      LinkFrame._(
        type: LinkFrameType.ack,
        src: src,
        dst: dst,
        msgId: msgId,
        index: index,
      );

  factory LinkFrame.nack({
    required int src,
    required int dst,
    required int msgId,
    required int index,
    int reason = NackReason.crcFailure,
  }) =>
      LinkFrame._(
        type: LinkFrameType.nack,
        src: src,
        dst: dst,
        msgId: msgId,
        index: index,
        reason: reason & 0xFF,
      );

  bool get ackRequested => (flags & flagAckRequested) != 0;
  bool get isControl => type != LinkFrameType.data;

  /// True if a PHY payload is a link frame rather than legacy raw text.
  static bool isLinkPayload(Uint8List payload) =>
      payload.isNotEmpty && payload[0] == magic;

  Uint8List encode() {
    final out = Uint8List(headerLength + chunk.length);
    final b = ByteData.sublistView(out);
    out[0] = magic;
    b.setUint16(3, src, Endian.little);
    if (type == LinkFrameType.data) {
      out[1] = _typeData;
      out[2] = flags;
      b.setUint16(5, msgId, Endian.little);
      b.setUint16(7, index, Endian.little);
      b.setUint16(9, count, Endian.little);
      out.setRange(headerLength, out.length, chunk);
    } else {
      out[1] = type == LinkFrameType.ack ? _typeAck : _typeNack;
      out[2] = reason;
      b.setUint16(5, dst, Endian.little);
      b.setUint16(7, msgId, Endian.little);
      b.setUint16(9, index, Endian.little);
    }
    return out;
  }

  /// Parses a link frame; returns null for anything malformed.
  static LinkFrame? decode(Uint8List p) {
    if (p.length < headerLength || p[0] != magic) return null;
    final b = ByteData.sublistView(p);
    int u16(int o) => b.getUint16(o, Endian.little);
    switch (p[1]) {
      case _typeData:
        final count = u16(9), index = u16(7);
        final chunkLen = p.length - headerLength;
        if (count < 1 || index >= count || chunkLen < 1) return null;
        if (chunkLen > maxChunk) return null;
        return LinkFrame._(
          type: LinkFrameType.data,
          src: u16(3),
          msgId: u16(5),
          index: index,
          count: count,
          flags: p[2],
          chunk: Uint8List.fromList(p.sublist(headerLength)),
        );
      case _typeAck:
      case _typeNack:
        if (p.length != headerLength) return null;
        return LinkFrame._(
          type: p[1] == _typeAck ? LinkFrameType.ack : LinkFrameType.nack,
          src: u16(3),
          dst: u16(5),
          msgId: u16(7),
          index: u16(9),
          reason: p[2],
        );
      default:
        return null;
    }
  }

  @override
  String toString() => type == LinkFrameType.data
      ? 'DATA(src=$src msg=$msgId ${index + 1}/$count '
          '${chunk.length}B${ackRequested ? ' ack-req' : ''})'
      : '${type.name.toUpperCase()}(src=$src dst=$dst msg=$msgId '
          'idx=$index)';
}

enum PayloadKind { text, file }

/// A link-layer message: the unit that is fragmented and reassembled.
///
/// Envelope (the byte string that gets fragmented):
///   0 kind (1 = text, 2 = file) | 1-4 content length | 5-8 CRC-32(content)
///   file only: name length (u8) | name (UTF-8) | MIME length (u8) | MIME
///   content
class LinkMessage {
  /// PRD F-22: binary payloads up to 1 MB.
  static const int maxContentBytes = 1 << 20;
  static const String defaultMime = 'application/octet-stream';

  static const int _kindText = 1, _kindFile = 2;

  final PayloadKind kind;
  final Uint8List content;
  final String? fileName;
  final String? mimeType;

  LinkMessage._(this.kind, this.content, this.fileName, this.mimeType) {
    if (content.length > maxContentBytes) {
      throw ArgumentError.value(content.length, 'content.length',
          'exceeds the $maxContentBytes byte limit');
    }
  }

  factory LinkMessage.text(String text) => LinkMessage._(
      PayloadKind.text, Uint8List.fromList(utf8.encode(text)), null, null);

  factory LinkMessage.file(
    Uint8List data, {
    required String fileName,
    String mimeType = defaultMime,
  }) =>
      LinkMessage._(PayloadKind.file, Uint8List.fromList(data),
          _bounded(fileName, 255), _bounded(mimeType, 255));

  String get text => utf8.decode(content, allowMalformed: true);

  Uint8List encode() {
    final meta = <int>[];
    if (kind == PayloadKind.file) {
      final name = utf8.encode(fileName ?? '');
      final mime = utf8.encode(mimeType ?? defaultMime);
      meta
        ..add(name.length)
        ..addAll(name)
        ..add(mime.length)
        ..addAll(mime);
    }
    final out = Uint8List(9 + meta.length + content.length);
    final b = ByteData.sublistView(out);
    out[0] = kind == PayloadKind.text ? _kindText : _kindFile;
    b.setUint32(1, content.length, Endian.little);
    b.setUint32(5, Crc32.compute(content), Endian.little);
    out.setRange(9, 9 + meta.length, meta);
    out.setRange(9 + meta.length, out.length, content);
    return out;
  }

  /// Parses and verifies an envelope. Throws [FormatException] if it is
  /// truncated, oversized or fails its CRC.
  static LinkMessage decode(Uint8List e) {
    if (e.length < 9) throw const FormatException('envelope too short');
    final b = ByteData.sublistView(e);
    final kindByte = e[0];
    if (kindByte != _kindText && kindByte != _kindFile) {
      throw FormatException('unknown payload kind $kindByte');
    }
    final length = b.getUint32(1, Endian.little);
    final crc = b.getUint32(5, Endian.little);
    if (length > maxContentBytes) {
      throw FormatException('content length $length exceeds limit');
    }
    var off = 9;
    String? name, mime;
    if (kindByte == _kindFile) {
      String field() {
        if (off >= e.length) throw const FormatException('truncated header');
        final n = e[off++];
        if (off + n > e.length) throw const FormatException('truncated name');
        final s = utf8.decode(e.sublist(off, off + n), allowMalformed: true);
        off += n;
        return s;
      }

      name = field();
      mime = field();
    }
    if (e.length - off != length) {
      throw FormatException(
          'content is ${e.length - off} bytes, header says $length');
    }
    final content = Uint8List.fromList(e.sublist(off));
    if (Crc32.compute(content) != crc) {
      throw const FormatException('message CRC-32 mismatch');
    }
    return LinkMessage._(
      kindByte == _kindText ? PayloadKind.text : PayloadKind.file,
      content,
      name,
      mime,
    );
  }

  /// Truncates [s] (by whole characters) to at most [maxBytes] UTF-8 bytes.
  static String _bounded(String s, int maxBytes) {
    if (utf8.encode(s).length <= maxBytes) return s;
    final runes = s.runes.toList();
    var n = runes.length < maxBytes ? runes.length : maxBytes;
    while (n > 0 &&
        utf8.encode(String.fromCharCodes(runes.take(n))).length > maxBytes) {
      n--;
    }
    return String.fromCharCodes(runes.take(n));
  }
}
