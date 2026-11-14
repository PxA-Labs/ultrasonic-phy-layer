// WAV file recorder — streams audio to a 16-bit mono PCM WAV file.
//
// startRecording() writes a placeholder header, addSamples() appends PCM as
// audio arrives, and stopRecording() patches the RIFF and data size fields in
// place, so the file is valid without buffering the whole recording in memory.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'wav_format.dart';

class WavRecorder {
  WavRecorder({this.sampleRate = 44100}) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
  }

  /// Sample rate written to the header; must match the audio being added.
  final int sampleRate;

  File? _file;
  RandomAccessFile? _raf;
  int _dataBytes = 0;
  bool _truncated = false;
  Object? _writeError;

  /// Writes are chained so chunks land in order even though [addSamples] is
  /// called synchronously from a stream listener.
  Future<void> _pending = Future<void>.value();

  bool get isRecording => _raf != null;

  /// Path of the file being written (null when not recording).
  String? get path => _file?.path;

  /// Samples appended so far.
  int get samplesWritten => _dataBytes ~/ 2;

  Duration get duration {
    final us = samplesWritten * Duration.microsecondsPerSecond;
    return Duration(microseconds: us ~/ sampleRate);
  }

  /// True if samples were dropped because the RIFF 4 GiB limit was reached.
  bool get truncated => _truncated;

  /// `soundwave_recording_YYYYMMDD_HHmmss.wav`
  static String fileNameFor(DateTime t) =>
      'soundwave_recording_${timestampForFileName(t)}.wav';

  /// Creates `soundwave_recording_<timestamp>.wav` in [directory] (created if
  /// needed) and returns its path. A numeric suffix avoids overwriting a
  /// recording started within the same second.
  Future<String> startRecording(Directory directory, {DateTime? now}) async {
    if (isRecording) throw StateError('Already recording to $path');
    await directory.create(recursive: true);
    final name = fileNameFor(now ?? DateTime.now());
    final stem = name.substring(0, name.length - 4);
    final sep = Platform.pathSeparator;
    var file = File('${directory.path}$sep$name');
    for (var i = 1; await file.exists(); i++) {
      file = File('${directory.path}$sep${stem}_$i.wav');
    }
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.writeFrom(buildWavHeader(0, sampleRate: sampleRate));
    } catch (_) {
      await raf.close();
      rethrow;
    }
    _file = file;
    _raf = raf;
    _dataBytes = 0;
    _truncated = false;
    _writeError = null;
    _pending = Future<void>.value();
    return file.path;
  }

  /// Appends [samples] (in [-1, 1]) to the recording. Ignored when not
  /// recording. Returns a future that completes once they are on disk.
  Future<void> addSamples(List<double> samples) {
    final raf = _raf;
    if (raf == null || samples.isEmpty) return _pending;
    var bytes = encodePcm16(samples);
    final room = wavMaxDataLength - _dataBytes;
    if (bytes.length > room) {
      _truncated = true;
      bytes = Uint8List.sublistView(bytes, 0, room - room % 2);
      if (bytes.isEmpty) return _pending;
    }
    _dataBytes += bytes.length;
    _pending = _pending.then((_) async {
      if (_writeError != null) return;
      try {
        await raf.writeFrom(bytes);
      } catch (e) {
        _writeError = e;
      }
    });
    return _pending;
  }

  /// Finalises the header and closes the file. Throws [StateError] when not
  /// recording, or the first write error after closing the file.
  Future<File> stopRecording() async {
    final raf = _raf;
    final file = _file;
    if (raf == null || file == null) throw StateError('Not recording');
    _raf = null;
    _file = null;
    try {
      await _pending;
      final sizes = ByteData(4);
      sizes.setUint32(0, 36 + _dataBytes, Endian.little);
      await raf.setPosition(4);
      await raf.writeFrom(sizes.buffer.asUint8List());
      sizes.setUint32(0, _dataBytes, Endian.little);
      await raf.setPosition(40);
      await raf.writeFrom(sizes.buffer.asUint8List());
      await raf.flush();
    } finally {
      await raf.close();
    }
    final error = _writeError;
    if (error != null) throw error;
    return file;
  }
}

/// `YYYYMMDD_HHmmss` in local time, used for all generated file names.
String timestampForFileName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final y = t.year.toString().padLeft(4, '0');
  final date = '$y${two(t.month)}${two(t.day)}';
  return '${date}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
