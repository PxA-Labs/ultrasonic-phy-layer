// Saving captured signal samples: a rolling buffer of the most recent capture
// audio, and a store that writes it as WAV plus a JSON metadata sidecar.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'message_exporter.dart';
import 'soundwave_storage.dart';
import 'wav_format.dart';
import 'wav_recorder.dart' show timestampForFileName;

/// Fixed-capacity ring buffer that keeps the last [capacity] samples.
class RollingSampleBuffer {
  RollingSampleBuffer(this.capacity) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
    _data = Float64List(capacity);
  }

  final int capacity;
  late final Float64List _data;
  int _start = 0;
  int _length = 0;

  int get length => _length;
  bool get isEmpty => _length == 0;

  void add(List<double> samples) {
    var src = 0;
    if (samples.length > capacity) {
      // Only the newest [capacity] samples can survive.
      src = samples.length - capacity;
      _start = 0;
      _length = 0;
    }
    for (var i = src; i < samples.length; i++) {
      final end = (_start + _length) % capacity;
      _data[end] = samples[i];
      if (_length < capacity) {
        _length++;
      } else {
        _start = (_start + 1) % capacity;
      }
    }
  }

  /// The buffered samples, oldest first.
  Float64List snapshot() {
    final out = Float64List(_length);
    for (var i = 0; i < _length; i++) {
      out[i] = _data[(_start + i) % capacity];
    }
    return out;
  }

  void clear() {
    _start = 0;
    _length = 0;
  }
}

/// Paths of a saved signal sample.
class SavedSignalSample {
  final File wav;
  final File metadata;
  const SavedSignalSample(this.wav, this.metadata);
}

class SignalSampleStore {
  SignalSampleStore(this.storage);

  final SoundwaveStorage storage;

  /// Writes `signal_YYYYMMDD_HHmmss.wav` (16-bit PCM) and a `.json` sidecar
  /// with timestamp, note, audio parameters and, when given, the decoded
  /// [message] (text, SNR, modulation mode, bytes) to `samples/`.
  Future<SavedSignalSample> save(
    Float64List samples, {
    required int sampleRate,
    String note = '',
    MessageRecord? message,
    DateTime? now,
  }) async {
    if (samples.isEmpty) throw ArgumentError('No samples to save');
    final at = now ?? DateTime.now();
    final dir = await storage.directory(StorageArea.samples);
    final sep = Platform.pathSeparator;
    var base = '${dir.path}${sep}signal_${timestampForFileName(at)}';
    final stem = base;
    for (var i = 1; await File('$base.wav').exists(); i++) {
      base = '${stem}_$i';
    }
    final wav = File('$base.wav');
    await wav.writeAsBytes(
      encodeWav(samples, sampleRate: sampleRate),
      flush: true,
    );
    final meta = <String, Object?>{
      'timestamp': at.toUtc().toIso8601String(),
      'note': note,
      'file': wav.uri.pathSegments.last,
      'sample_rate': sampleRate,
      'samples': samples.length,
      'duration_s': samples.length / sampleRate,
      'format': 'WAV PCM 16-bit mono',
      'snr': message == null || !message.snr.isFinite ? null : message.snr,
      'decoded_text': message?.text,
      'mode': message?.mode,
      'message': message?.toJson(),
    };
    final metadata = File('$base.json');
    const encoder = JsonEncoder.withIndent('  ');
    await metadata.writeAsString(encoder.convert(meta), flush: true);
    return SavedSignalSample(wav, metadata);
  }
}
