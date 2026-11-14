// WAV (RIFF/WAVE) encoding and parsing shared by the recorder, the signal
// importer and the signal-sample store.
//
// Writing: 16-bit PCM (the recording format required by #33) or 32-bit IEEE
// float (lossless export of modulated signals).
// Reading: PCM 8/16/24/32-bit, IEEE float 32/64-bit and WAVE_FORMAT_EXTENSIBLE,
// any number of channels (mixed down to mono), unknown chunks (LIST, fact,
// ...) skipped, and recordings whose header sizes were never finalised.

import 'dart:typed_data';

/// WAVE format tags.
class WavFormatTag {
  static const int pcm = 1;
  static const int ieeeFloat = 3;
  static const int extensible = 0xFFFE;
}

/// Sample encodings supported when writing a WAV file.
enum WavSampleFormat { pcm16, float32 }

/// Size of the canonical header written by [buildWavHeader].
const int wavHeaderLength = 44;

/// Largest data chunk a RIFF file can describe (its size fields are uint32).
const int wavMaxDataLength = 0xFFFFFFFF - 36;

/// Builds the canonical 44-byte header for a mono or multi-channel file with
/// [dataLength] bytes of sample data.
Uint8List buildWavHeader(
  int dataLength, {
  int sampleRate = 44100,
  int channels = 1,
  WavSampleFormat format = WavSampleFormat.pcm16,
}) {
  if (dataLength < 0 || dataLength > wavMaxDataLength) {
    throw RangeError.range(dataLength, 0, wavMaxDataLength, 'dataLength');
  }
  if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
  if (channels <= 0) throw ArgumentError.value(channels, 'channels');
  final isPcm16 = format == WavSampleFormat.pcm16;
  final bits = isPcm16 ? 16 : 32;
  final tag = isPcm16 ? WavFormatTag.pcm : WavFormatTag.ieeeFloat;
  final blockAlign = channels * bits ~/ 8;
  final header = ByteData(wavHeaderLength);
  header.setUint32(0, 0x46464952, Endian.little); // "RIFF"
  header.setUint32(4, 36 + dataLength, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little); // "WAVE"
  header.setUint32(12, 0x20746D66, Endian.little); // "fmt "
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, tag, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * blockAlign, Endian.little); // byte rate
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bits, Endian.little);
  header.setUint32(36, 0x61746164, Endian.little); // "data"
  header.setUint32(40, dataLength, Endian.little);
  return header.buffer.asUint8List();
}

/// Quantises one sample in [-1, 1] to a signed 16-bit value.
///
/// Uses the 2^15 scale (the inverse of the /32768 used when reading) so a
/// round trip is accurate to half an LSB; +1.0 clips to 32767.
int pcm16FromDouble(double s) {
  if (s.isNaN) return 0;
  final v = (s * 32768.0).round();
  return v.clamp(-32768, 32767);
}

/// Encodes [samples] as little-endian 16-bit PCM.
Uint8List encodePcm16(List<double> samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(i * 2, pcm16FromDouble(samples[i]), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Encodes [samples] as little-endian 32-bit IEEE float.
Uint8List encodeFloat32(List<double> samples) {
  final out = ByteData(samples.length * 4);
  for (var i = 0; i < samples.length; i++) {
    out.setFloat32(i * 4, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Encodes a complete mono WAV file.
Uint8List encodeWav(
  List<double> samples, {
  int sampleRate = 44100,
  WavSampleFormat format = WavSampleFormat.pcm16,
}) {
  final Uint8List data;
  if (format == WavSampleFormat.pcm16) {
    data = encodePcm16(samples);
  } else {
    data = encodeFloat32(samples);
  }
  final header = buildWavHeader(
    data.length,
    sampleRate: sampleRate,
    format: format,
  );
  final out = Uint8List(header.length + data.length);
  out.setRange(0, header.length, header);
  out.setRange(header.length, out.length, data);
  return out;
}

/// Decoded contents of a WAV file.
class WavAudio {
  /// Mono samples in [-1, 1] (multi-channel files are averaged).
  final Float64List samples;
  final int sampleRate;

  /// Channel count of the source file (before the mono mix-down).
  final int channels;
  final int bitsPerSample;

  /// [WavFormatTag.pcm] or [WavFormatTag.ieeeFloat] (extensible resolved).
  final int formatTag;

  /// True when the header sizes were missing or wrong (e.g. a recording
  /// that was interrupted before its header was finalised).
  final bool sizeRepaired;

  const WavAudio({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.formatTag,
    this.sizeRepaired = false,
  });

  Duration get duration {
    final us = samples.length * Duration.microsecondsPerSecond;
    return Duration(microseconds: us ~/ sampleRate);
  }
}

String _fourCc(Uint8List b, int offset) =>
    String.fromCharCodes(b.sublist(offset, offset + 4));

/// Parses a WAV file. Throws [FormatException] for anything that is not a
/// readable RIFF/WAVE file.
WavAudio parseWav(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  if (bytes.length < 12) throw const FormatException('File too short');
  if (_fourCc(bytes, 0) != 'RIFF' || _fourCc(bytes, 8) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int? tag, channels, sampleRate, bits;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _fourCc(bytes, offset);
    final size = d.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      if (size < 16 || body + 16 > bytes.length) {
        throw const FormatException('Truncated fmt chunk');
      }
      tag = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      sampleRate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (tag == WavFormatTag.extensible) {
        // WAVEFORMATEXTENSIBLE: the sub-format GUID starts at byte 24 of the
        // chunk and its first two bytes are the actual format tag.
        if (size < 40 || body + 26 > bytes.length) {
          throw const FormatException('Truncated WAVE_FORMAT_EXTENSIBLE');
        }
        tag = d.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (tag == null) {
        throw const FormatException('data chunk before fmt chunk');
      }
      final available = bytes.length - body;
      // A recording that was never finalised has 0 (or 0xFFFFFFFF, as some
      // streaming writers use) in its size fields: take the rest of the file.
      final repaired = size == 0 || size > available;
      final length = repaired ? available : size;
      return _decodeData(
        d,
        body,
        length,
        tag: tag,
        channels: channels!,
        sampleRate: sampleRate!,
        bits: bits!,
        repaired: repaired && available > 0,
      );
    }
    // Chunks are word aligned: odd sizes are followed by a pad byte.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('No data chunk');
}

WavAudio _decodeData(
  ByteData d,
  int start,
  int length, {
  required int tag,
  required int channels,
  required int sampleRate,
  required int bits,
  required bool repaired,
}) {
  if (channels <= 0) throw const FormatException('Invalid channel count');
  if (sampleRate <= 0) throw const FormatException('Invalid sample rate');
  final pcmBits = bits == 8 || bits == 16 || bits == 24 || bits == 32;
  final isPcm = tag == WavFormatTag.pcm && pcmBits;
  final isFloat = tag == WavFormatTag.ieeeFloat && (bits == 32 || bits == 64);
  if (!isPcm && !isFloat) {
    throw FormatException('Unsupported WAV encoding (tag $tag, $bits bit)');
  }
  final bytesPerSample = bits ~/ 8;
  final frameBytes = bytesPerSample * channels;
  final frames = length ~/ frameBytes;
  final out = Float64List(frames);

  double read(int o) {
    if (isFloat) {
      if (bits == 32) return d.getFloat32(o, Endian.little);
      return d.getFloat64(o, Endian.little);
    }
    switch (bits) {
      case 8:
        return (d.getUint8(o) - 128) / 128.0; // 8-bit PCM is unsigned
      case 16:
        return d.getInt16(o, Endian.little) / 32768.0;
      case 24:
        final lo = d.getUint16(o, Endian.little);
        final hi = d.getInt8(o + 2); // sign-extends the top byte
        return (hi * 65536 + lo) / 8388608.0;
      default:
        return d.getInt32(o, Endian.little) / 2147483648.0;
    }
  }

  for (var f = 0; f < frames; f++) {
    final base = start + f * frameBytes;
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += read(base + c * bytesPerSample);
    }
    out[f] = sum / channels;
  }
  return WavAudio(
    samples: out,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bits,
    formatTag: tag,
    sizeRepaired: repaired,
  );
}
