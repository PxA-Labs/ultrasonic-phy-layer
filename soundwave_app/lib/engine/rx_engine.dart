// RX Engine — captures audio, detects frames, demodulates, and decodes messages.

import 'dart:typed_data';

class DecodedMessage {
  final String text;
  final double snr;
  final DateTime timestamp;
  final Uint8List rawBytes;

  const DecodedMessage({
    required this.text,
    required this.snr,
    required this.timestamp,
    required this.rawBytes,
  });
}

class RxEngine {
  Stream<DecodedMessage> startListening() async* {
    // TODO: capture audio -> detect frame -> demodulate -> yield DecodedMessage
  }

  void stopListening() {
    // TODO
  }
}
