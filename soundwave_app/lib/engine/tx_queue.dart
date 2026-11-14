// TX Queue — schedules and controls sequential transmission queues.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'tx_engine.dart';

class QueuedMessage {
  final String text;
  final DateTime? scheduledAt;

  /// Binary payload for a file transfer (#89); null for text messages.
  final Uint8List? data;
  final String? fileName;
  final String? mimeType;
  final Completer<void> _done = Completer<void>();

  QueuedMessage(this.text, this.scheduledAt,
      {this.data, this.fileName, this.mimeType});

  /// Completes when this message has been sent, or with its error.
  Future<void> get done => _done.future;
}

class TxQueue {
  final TxEngine txEngine;
  final Queue<QueuedMessage> _queue = Queue();
  bool _isTransmitting = false;

  TxQueue({required this.txEngine});

  List<QueuedMessage> get queuedMessages => _queue.toList();

  Future<void> enqueue(String message, {DateTime? scheduledAt}) async {
    final msg = QueuedMessage(message, scheduledAt);
    msg.done.ignore(); // text errors are logged by the queue, as before
    _add(msg);
  }

  /// Queues a binary file transfer. The returned future completes when the
  /// transfer finishes and fails with its error (e.g. TxMaxRetriesError).
  Future<void> enqueueFile(
    Uint8List data, {
    required String fileName,
    required String mimeType,
    DateTime? scheduledAt,
  }) {
    final msg = QueuedMessage(fileName, scheduledAt,
        data: data, fileName: fileName, mimeType: mimeType);
    _add(msg);
    return msg.done;
  }

  void _add(QueuedMessage msg) {
    _queue.add(msg);
    if (!_isTransmitting) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    _isTransmitting = true;
    while (_queue.isNotEmpty) {
      final msg = _queue.removeFirst();
      if (msg.scheduledAt != null && msg.scheduledAt!.isAfter(DateTime.now())) {
        final diff = msg.scheduledAt!.difference(DateTime.now());
        await Future.delayed(diff);
      }
      try {
        final data = msg.data;
        if (data != null) {
          await txEngine.sendBinary(data,
              fileName: msg.fileName ?? 'data.bin',
              mimeType: msg.mimeType ?? 'application/octet-stream');
        } else {
          await txEngine.sendMessage(msg.text);
        }
        msg._done.complete();
      } catch (e, st) {
        print('TX Queue failed transmitting message: $e');
        msg._done.completeError(e, st);
      }
    }
    _isTransmitting = false;
  }
}
