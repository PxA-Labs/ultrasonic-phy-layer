// Message exporter — writes decoded messages as JSON, CSV or plain text.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../engine/rx_engine.dart';
import 'wav_recorder.dart' show timestampForFileName;

/// A decoded message plus the modulation mode it was received with.
class MessageRecord {
  final String text;
  final double snr;
  final DateTime timestamp;
  final Uint8List bytes;

  /// "CSS" or "OFDM".
  final String mode;

  const MessageRecord({
    required this.text,
    required this.snr,
    required this.timestamp,
    required this.bytes,
    required this.mode,
  });

  factory MessageRecord.fromDecoded(DecodedMessage m, {required String mode}) {
    return MessageRecord(
      text: m.text,
      snr: m.snr,
      timestamp: m.timestamp,
      bytes: m.rawBytes,
      mode: mode,
    );
  }

  /// JSON form used by the JSON export and signal-sample sidecars.
  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'text': text,
        // JSON has no NaN/Infinity.
        'snr': snr.isFinite ? snr : null,
        'mode': mode,
        'bytes': bytes.toList(),
      };
}

enum ExportFormat {
  json('json'),
  csv('csv'),
  text('txt');

  const ExportFormat(this.extension);

  /// File extension, without the dot.
  final String extension;
}

class MessageExporter {
  const MessageExporter();

  // ---- Rendering --------------------------------------------------------

  /// `[{"timestamp": ISO-8601 UTC, "text", "snr", "mode", "bytes"}]`
  String toJson(List<MessageRecord> messages) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert([for (final m in messages) m.toJson()]);
  }

  /// RFC 4180 CSV with a `timestamp,text,snr,mode` header.
  String toCsv(List<MessageRecord> messages) {
    final buf = StringBuffer('timestamp,text,snr,mode\r\n');
    for (final m in messages) {
      final ts = m.timestamp.toUtc().toIso8601String();
      buf.write('$ts,${_csvText(m.text)},${_snr(m.snr)},${m.mode}\r\n');
    }
    return buf.toString();
  }

  /// `[YYYY-MM-DD HH:mm:ss] text (SNR: 12.3 dB, CSS)` per line, local time.
  String toText(List<MessageRecord> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final ts = formatLogTimestamp(m.timestamp);
      // Keep one message per line even if the payload contains newlines.
      final text = m.text.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
      buf.writeln('[$ts] $text (SNR: ${_snr(m.snr)} dB, ${m.mode})');
    }
    return buf.toString();
  }

  String render(List<MessageRecord> messages, ExportFormat format) {
    switch (format) {
      case ExportFormat.json:
        return toJson(messages);
      case ExportFormat.csv:
        return toCsv(messages);
      case ExportFormat.text:
        return toText(messages);
    }
  }

  // ---- Files ------------------------------------------------------------

  Future<File> exportAsJson(List<MessageRecord> messages, String path) =>
      _write(path, toJson(messages));

  Future<File> exportAsCsv(List<MessageRecord> messages, String path) =>
      _write(path, toCsv(messages));

  Future<File> exportAsText(List<MessageRecord> messages, String path) =>
      _write(path, toText(messages));

  /// Writes `soundwave_messages_YYYYMMDD_HHmmss.<ext>` into [directory].
  Future<File> export(
    List<MessageRecord> messages,
    ExportFormat format,
    Directory directory, {
    DateTime? now,
  }) async {
    await directory.create(recursive: true);
    final stamp = timestampForFileName(now ?? DateTime.now());
    final sep = Platform.pathSeparator;
    final base = '${directory.path}${sep}soundwave_messages_$stamp';
    var path = '$base.${format.extension}';
    for (var i = 1; await File(path).exists(); i++) {
      path = '${base}_$i.${format.extension}';
    }
    return _write(path, render(messages, format));
  }

  Future<File> _write(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content, flush: true);
    return file;
  }

  static String _snr(double snr) =>
      snr.isFinite ? snr.toStringAsFixed(1) : 'NaN';

  /// Quotes a CSV field, doubling embedded quotes. Text starting with a
  /// spreadsheet formula trigger (= + - @ tab CR) is prefixed with `'` so a
  /// received payload cannot inject a formula when the log is opened.
  static String _csvText(String text) {
    var t = text;
    if (t.isNotEmpty && '=+-@\t\r'.contains(t[0])) t = "'$t";
    return '"${t.replaceAll('"', '""')}"';
  }
}

/// `YYYY-MM-DD HH:mm:ss` in local time.
String formatLogTimestamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final y = l.year.toString().padLeft(4, '0');
  final date = '$y-${two(l.month)}-${two(l.day)}';
  final time = '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  return '$date $time';
}
