// Message exporter — exports decoded messages as JSON, CSV, or plain text.

import 'dart:convert';
import 'dart:io';
import '../engine/rx_engine.dart';

class MessageExporter {
  Future<File> exportAsJson(List<DecodedMessage> messages, String path) async {
    final json = jsonEncode(messages.map((m) => {
      'timestamp': m.timestamp.toIso8601String(),
      'text': m.text,
      'snr': m.snr,
      'mode': 'CSS',
      'bytes': m.rawBytes.toList(),
    }).toList());
    return File(path)..writeAsStringSync(json);
  }

  Future<File> exportAsCsv(List<DecodedMessage> messages, String path) async {
    final buf = StringBuffer('timestamp,text,snr,mode\n');
    for (final m in messages) {
      buf.writeln('${m.timestamp.toIso8601String()},"${m.text}",${m.snr},CSS');
    }
    return File(path)..writeAsStringSync(buf.toString());
  }

  Future<File> exportAsText(List<DecodedMessage> messages, String path) async {
    final buf = StringBuffer();
    for (final m in messages) {
      buf.writeln('[${m.timestamp}] ${m.text} (SNR: ${m.snr.toStringAsFixed(1)} dB)');
    }
    return File(path)..writeAsStringSync(buf.toString());
  }
}
