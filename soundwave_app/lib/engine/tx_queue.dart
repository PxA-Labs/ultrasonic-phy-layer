// TX Queue — schedules and controls sequential transmission queues.

import 'dart:collection';
import 'tx_engine.dart';

class QueuedMessage {
  final String text;
  final DateTime? scheduledAt;

  const QueuedMessage(this.text, this.scheduledAt);
}

class TxQueue {
  final TxEngine txEngine;
  final Queue<QueuedMessage> _queue = Queue();
  bool _isTransmitting = false;

  TxQueue({required this.txEngine});

  List<QueuedMessage> get queuedMessages => _queue.toList();

  Future<void> enqueue(String message, {DateTime? scheduledAt}) async {
    _queue.add(QueuedMessage(message, scheduledAt));
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
        await txEngine.sendMessage(msg.text);
      } catch (e) {
        print('TX Queue failed transmitting message: $e');
      }
    }
    _isTransmitting = false;
  }
}
