// WAV file recorder — captures audio to 16-bit mono PCM WAV files.

import 'dart:io';
import 'dart:typed_data';

class WavRecorder {
  File? _file;
  int _bytesWritten = 0;
  static const int _sampleRate = 44100;

  Future<String> startRecording(String directory) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = '${directory}soundwave_${DateTime.now().millisecondsSinceEpoch}.wav';
    _file = File(path);
    // Write placeholder header (44 bytes, will overwrite at stop)
    await _file!.writeAsBytes(Uint8List(44));
    _bytesWritten = 44;
    return path;
  }

  Future<File> stopRecording() async {
    if (_file == null) throw Exception('Not recording');
    // Write WAV header at start
    final dataLength = _bytesWritten - 44;
    final header = _buildWavHeader(dataLength);
    await _file!.writeAsBytes(header, mode: FileMode.write, flush: true);
    // Re-append data
    // TODO: proper implementation with actual audio samples
    final f = _file!;
    _file = null;
    return f;
  }

  Uint8List _buildWavHeader(int dataLength) {
    final header = ByteData(44);
    header.setUint32(0, 0x46464952, Endian.little); // RIFF
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint32(8, 0x45564157, Endian.little); // WAVE
    header.setUint32(12, 0x20746D66, Endian.little); // fmt_
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    header.setUint32(36, 0x61746164, Endian.little); // data
    header.setUint32(40, dataLength, Endian.little);
    return header.buffer.asUint8List();
  }
}
