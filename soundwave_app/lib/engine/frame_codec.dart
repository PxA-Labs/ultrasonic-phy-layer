// Frame codec — the byte-level frame format shared by TX and RX.
//
//   [CRC-32 (4 bytes, little-endian, over payload)][payload][RS parity (32)]
//
// RS parity is present only when enable_rs is on. The frame carries no length
// field, and the demodulator returns every symbol in its input (including
// trailing noise), so decode() searches for the frame length: for each
// candidate length it runs RS (if enabled) and accepts the first length whose
// CRC-32 verifies. CRC-32 + RS make a false accept vanishingly unlikely, and
// this keeps the on-air format unchanged.

import 'dart:typed_data';

import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

class DecodedFrame {
  final Uint8List payload;

  /// Total frame length in bytes (CRC + payload + parity).
  final int frameLength;
  final int errorsCorrected;

  const DecodedFrame({
    required this.payload,
    required this.frameLength,
    required this.errorsCorrected,
  });
}

class FrameCodec {
  static const int crcLength = 4;
  static const int parityLength = 32;

  /// RS(255,223): the codeword data part (CRC + payload) is at most 223 bytes.
  static const int maxPayload = 223 - crcLength;

  final SoundwaveNative native;

  const FrameCodec(this.native);

  /// Builds a frame for [payload]. Throws [ArgumentError] if it does not fit.
  Uint8List encode(Uint8List payload, {bool enableRs = true}) {
    if (payload.isEmpty || payload.length > maxPayload) {
      throw ArgumentError.value(payload.length, 'payload.length',
          'must be 1..$maxPayload bytes for a single frame');
    }
    final crc = native.crc32(payload);
    final packet = Uint8List(crcLength + payload.length);
    ByteData.sublistView(packet).setUint32(0, crc, Endian.little);
    packet.setRange(crcLength, packet.length, payload);
    if (!enableRs) return packet;

    final parity = native.rsEncode(packet);
    if (parity.length != parityLength) {
      throw StateError('RS encoder returned ${parity.length} parity bytes');
    }
    return Uint8List(packet.length + parityLength)
      ..setRange(0, packet.length, packet)
      ..setRange(packet.length, packet.length + parityLength, parity);
  }

  /// Finds and verifies the frame at the start of [bytes] (demodulator output,
  /// possibly followed by garbage). Returns null if no length verifies.
  DecodedFrame? decode(Uint8List bytes, {bool enableRs = true}) {
    final overhead = crcLength + (enableRs ? parityLength : 0);
    final maxLen = bytes.length < overhead + maxPayload
        ? bytes.length
        : overhead + maxPayload;

    for (var len = overhead + 1; len <= maxLen; len++) {
      Uint8List packet;
      var corrected = 0;
      if (enableRs) {
        final dataLen = len - parityLength;
        try {
          final res = native.rsDecode(
            Uint8List.sublistView(bytes, 0, dataLen),
            Uint8List.sublistView(bytes, dataLen, len),
          );
          packet = res['message'] as Uint8List;
          corrected = res['errors_corrected'] as int? ?? 0;
        } on SwException {
          continue; // uncorrectable at this length
        }
      } else {
        packet = Uint8List.sublistView(bytes, 0, len);
      }
      if (packet.length <= crcLength) continue;

      final stored = ByteData.sublistView(packet, 0, crcLength)
          .getUint32(0, Endian.little);
      final payload = Uint8List.fromList(packet.sublist(crcLength));
      if (native.crc32(payload) == stored) {
        return DecodedFrame(
          payload: payload,
          frameLength: len,
          errorsCorrected: corrected,
        );
      }
    }
    return null;
  }
}
