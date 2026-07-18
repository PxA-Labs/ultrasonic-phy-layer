// Message history — persists received messages to local storage (max 100 entries).

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'rx_engine.dart';

class MessageHistory {
  final List<DecodedMessage> _messages = [];
  static const int _maxEntries = 100;

  List<DecodedMessage> get messages => List.unmodifiable(_messages);

  void add(DecodedMessage msg) {
    _messages.insert(0, msg);
    if (_messages.length > _maxEntries) _messages.removeLast();
    _save();
  }

  Future<void> load() async {
    final file = await _getFile();
    if (!file.existsSync()) return;
    final json = jsonDecode(await file.readAsString()) as List;
    _messages.clear();
    for (final item in json) {
      _messages.add(DecodedMessage(
        text: item['text'] as String,
        snr: (item['snr'] as num).toDouble(),
        timestamp: DateTime.parse(item['timestamp'] as String),
        rawBytes: Uint8List.fromList((item['bytes'] as List).cast<int>()),
      ));
    }
  }

  Future<void> clear() async {
    _messages.clear();
    final file = await _getFile();
    if (file.existsSync()) await file.delete();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final swDir = Directory('${dir.path}/soundwave');
    if (!swDir.existsSync()) swDir.createSync();
    return File('${swDir.path}/message_history.json');
  }

  void _save() {
    _getFile().then((file) {
      final json = jsonEncode(_messages.map((m) => {
        'text': m.text,
        'snr': m.snr,
        'timestamp': m.timestamp.toIso8601String(),
        'bytes': m.rawBytes.toList(),
      }).toList());
      file.writeAsString(json);
    });
  }
}
