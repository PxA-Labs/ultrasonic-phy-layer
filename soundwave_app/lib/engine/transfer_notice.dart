// End-of-transfer notices for file transfers (issue #89): file name, size,
// transfer time and effective throughput, shown as a toast by the app shell.

import 'package:soundwave/export/soundwave_storage.dart';

enum TransferDirection { sent, received }

class TransferNotice {
  final TransferDirection direction;
  final String fileName;
  final int bytes;

  /// Wall-clock transfer time. Sent: first fragment handed to the PHY until
  /// the transfer finished (last ACK with ARQ). Received: start of the first
  /// fragment's frame until reassembly.
  final Duration duration;

  /// False when the transfer failed (sending) or the file could not be
  /// saved (receiving); [error] says why.
  final bool ok;
  final String? error;

  /// Retransmitted fragments (sent, ARQ only).
  final int retransmissions;

  const TransferNotice({
    required this.direction,
    required this.fileName,
    required this.bytes,
    required this.duration,
    this.ok = true,
    this.error,
    this.retransmissions = 0,
  });

  /// Payload bits per second over [duration], or null when it is too short
  /// to be meaningful.
  double? get bitsPerSecond {
    final us = duration.inMicroseconds;
    if (us < 50000) return null;
    return bytes * 8 * 1e6 / us;
  }

  /// One-line toast text.
  String get message {
    final name = '"$fileName"';
    if (!ok) {
      return direction == TransferDirection.sent
          ? 'Sending $name failed after ${formatTransferDuration(duration)}'
              '${error == null ? '' : ': $error'}'
          : 'Received $name but could not save it'
              '${error == null ? '' : ': $error'}';
    }
    final verb = direction == TransferDirection.sent ? 'Sent' : 'Received';
    final bps = bitsPerSecond;
    var text = '$verb $name (${formatBytes(bytes)})';
    if (duration > Duration.zero) {
      text += ' in ${formatTransferDuration(duration)}';
      if (bps != null) text += ' · ${formatBitRate(bps)}';
    }
    if (retransmissions > 0) {
      text += ' · $retransmissions '
          '${retransmissions == 1 ? 'retransmission' : 'retransmissions'}';
    }
    return text;
  }
}

/// `0.4 s`, `8.6 s`, `59.9 s`, `1 min 05 s`, `1 h 02 min`.
String formatTransferDuration(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 60000) {
    // Truncate (not round) so 59.96 s stays below a minute.
    final tenths = ms ~/ 100;
    return '${tenths ~/ 10}.${tenths % 10} s';
  }
  final totalSeconds = d.inSeconds;
  if (totalSeconds < 3600) {
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m min $s s';
  }
  final h = totalSeconds ~/ 3600;
  final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  return '$h h $m min';
}

/// `420 bit/s`, `11.5 kbit/s`, `1.20 Mbit/s`.
String formatBitRate(double bitsPerSecond) {
  if (bitsPerSecond < 1000) return '${bitsPerSecond.round()} bit/s';
  if (bitsPerSecond < 1e6) {
    return '${(bitsPerSecond / 1000).toStringAsFixed(1)} kbit/s';
  }
  return '${(bitsPerSecond / 1e6).toStringAsFixed(2)} Mbit/s';
}
