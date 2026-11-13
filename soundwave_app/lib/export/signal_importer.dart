// Signal importer — loads WAV or headerless 16-bit PCM files so a recorded or
// pre-modulated signal can be inspected and fed through the RX pipeline.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_format.dart' as wav;

/// A signal loaded from a file, normalised to mono samples in [-1, 1].
class ImportedSignal {
  final String name;
  final Float64List samples;
  final int sampleRate;

  /// Channels in the source file (samples are already mixed to mono).
  final int channels;
  final int bitsPerSample;

  /// Short description of the source encoding, e.g. "WAV PCM 16-bit".
  final String format;

  const ImportedSignal({
    required this.name,
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.format,
  });

  Duration get duration {
    final us = samples.length * Duration.microsecondsPerSecond;
    return Duration(microseconds: us ~/ sampleRate);
  }

  /// Largest absolute sample value.
  double get peak {
    var p = 0.0;
    for (final s in samples) {
      p = math.max(p, s.abs());
    }
    return p;
  }
}

class SignalImporter {
  /// Files larger than this are rejected (64 MiB ≈ 12 min of 16-bit audio
  /// at 44.1 kHz) to keep the decoded sample buffer within memory limits.
  static const int defaultMaxBytes = 64 * 1024 * 1024;

  final int maxBytes;

  const SignalImporter({this.maxBytes = defaultMaxBytes});

  /// Extensions offered in the file picker.
  static const List<String> extensions = ['wav', 'pcm', 'raw'];

  /// Parses [bytes] as a WAV file when it starts with a RIFF header and as
  /// headerless little-endian 16-bit mono PCM otherwise. [rawSampleRate] is
  /// used for headerless files, which carry no rate of their own.
  ImportedSignal parse(
    Uint8List bytes, {
    required String name,
    int rawSampleRate = 44100,
  }) {
    if (bytes.length > maxBytes) {
      throw FormatException(
        'File is too large (${bytes.length} bytes, limit $maxBytes)',
      );
    }
    if (_isRiff(bytes) || name.toLowerCase().endsWith('.wav')) {
      return parseWav(bytes, name: name);
    }
    return parseRawPcm(bytes, name: name, sampleRate: rawSampleRate);
  }

  ImportedSignal parseWav(Uint8List bytes, {String name = 'signal.wav'}) {
    final audio = wav.parseWav(bytes);
    final isFloat = audio.formatTag == wav.WavFormatTag.ieeeFloat;
    final kind = isFloat ? 'float' : 'PCM';
    return ImportedSignal(
      name: name,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
      channels: audio.channels,
      bitsPerSample: audio.bitsPerSample,
      format: 'WAV $kind ${audio.bitsPerSample}-bit',
    );
  }

  ImportedSignal parseRawPcm(
    Uint8List bytes, {
    String name = 'signal.raw',
    int sampleRate = 44100,
  }) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    return ImportedSignal(
      name: name,
      samples: decodeRawPcm16(bytes),
      sampleRate: sampleRate,
      channels: 1,
      bitsPerSample: 16,
      format: 'Raw PCM 16-bit',
    );
  }

  /// Reads and parses the file at [path] (see [parse]).
  Future<ImportedSignal> importFile(
    String path, {
    int rawSampleRate = 44100,
  }) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxBytes) {
      throw FormatException('File is too large ($length bytes)');
    }
    final name = file.uri.pathSegments.last;
    final bytes = await file.readAsBytes();
    return parse(bytes, name: name, rawSampleRate: rawSampleRate);
  }

  /// Loads a WAV file as mono samples in [-1, 1].
  Future<Float64List> importWav(String path) async {
    final signal = parseWav(await File(path).readAsBytes(), name: path);
    return signal.samples;
  }

  /// Loads headerless little-endian 16-bit mono PCM.
  Future<Float64List> importRawPcm(String path, int sampleRate) async {
    return decodeRawPcm16(await File(path).readAsBytes());
  }

  static bool _isRiff(Uint8List b) =>
      b.length >= 4 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF';

  /// Decodes little-endian 16-bit PCM; a trailing odd byte is ignored.
  static Float64List decodeRawPcm16(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    final samples = Float64List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = d.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }
}
