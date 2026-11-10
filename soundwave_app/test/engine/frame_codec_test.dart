// Unit tests for FrameCodec using the mock native layer
// (mock CRC = byte sum, mock RS = 32 x 0xAA parity, decode = passthrough).

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'mock_native.dart';

void main() {
  final codec = FrameCodec(MockSoundwaveNative());

  group('FrameCodec', () {
    test('encode lays out [CRC LE][payload][parity]', () {
      final f = codec.encode(Uint8List.fromList([1, 2, 3]));
      expect(f.length, 4 + 3 + 32);
      expect(f.sublist(0, 4), [6, 0, 0, 0]); // mock CRC = 6, little-endian
      expect(f.sublist(4, 7), [1, 2, 3]);
      expect(f.sublist(7), List.filled(32, 0xAA));
    });

    test('encode without RS omits parity', () {
      final f = codec.encode(Uint8List.fromList([1, 2, 3]), enableRs: false);
      expect(f, [6, 0, 0, 0, 1, 2, 3]);
    });

    test('encode rejects empty and oversized payloads', () {
      expect(() => codec.encode(Uint8List(0)), throwsArgumentError);
      expect(() => codec.encode(Uint8List(FrameCodec.maxPayload + 1)),
          throwsArgumentError);
      expect(codec.encode(Uint8List(FrameCodec.maxPayload)).length, 255);
    });

    test('decode finds the frame inside trailing garbage', () {
      final f = codec.encode(Uint8List.fromList([1, 2, 3]));
      final withTail = Uint8List.fromList([...f, 9, 9, 9, 9, 9]);
      final d = codec.decode(withTail);
      expect(d, isNotNull);
      expect(d!.payload, [1, 2, 3]);
      expect(d.frameLength, f.length);
    });

    test('decode round-trips without RS', () {
      final f = codec.encode(Uint8List.fromList([10, 20]), enableRs: false);
      final d = codec.decode(Uint8List.fromList([...f, 0xFF]), enableRs: false);
      expect(d?.payload, [10, 20]);
    });

    test('decode returns null when no length verifies', () {
      expect(codec.decode(Uint8List.fromList(List.filled(80, 0x5A))), isNull);
      expect(codec.decode(Uint8List(10)), isNull); // shorter than overhead
    });
  });
}
