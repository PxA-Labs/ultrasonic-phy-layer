// TX Engine — encodes messages into frames and modulates via native DSP.

import 'dart:typed_data';

class TxEngine {
  Future<void> sendMessage(String text) async {
    final bytes = Uint8List.fromList(text.codeUnits);
    // TODO: CRC, RS encode, modulate via SoundwaveNative, play via AudioService
  }
}
