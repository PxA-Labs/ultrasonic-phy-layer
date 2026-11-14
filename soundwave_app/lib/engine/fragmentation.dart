// Payload fragmentation and reassembly (#89).
//
// A [LinkMessage] envelope is split into DATA [LinkFrame]s of at most
// [LinkFrame.maxChunk] bytes. The receiver buffers fragments per
// (source node, message id), tolerates any order and duplicates, and delivers
// the message once every fragment has arrived and the message CRC-32
// verifies. Incomplete messages are dropped after an idle timeout and
// reported as [ReassemblyFailure]s. Pure Dart; time is passed in explicitly.

import 'dart:collection';
import 'dart:typed_data';

import 'package:soundwave/engine/link_frame.dart';

class PayloadFragmenter {
  final int maxChunk;

  PayloadFragmenter({this.maxChunk = LinkFrame.maxChunk}) {
    if (maxChunk < 1 || maxChunk > LinkFrame.maxChunk) {
      throw ArgumentError.value(
          maxChunk, 'maxChunk', 'must be 1..${LinkFrame.maxChunk}');
    }
  }

  static int fragmentCount(int envelopeBytes, int maxChunk) =>
      (envelopeBytes + maxChunk - 1) ~/ maxChunk;

  List<LinkFrame> fragment(
    LinkMessage message, {
    required int src,
    required int msgId,
    bool ackRequested = false,
  }) {
    final envelope = message.encode();
    final count = fragmentCount(envelope.length, maxChunk);
    if (count > 0xFFFF) {
      throw ArgumentError('message needs $count fragments (max 65535)');
    }
    return [
      for (var i = 0; i < count; i++)
        LinkFrame.data(
          src: src,
          msgId: msgId,
          index: i,
          count: count,
          ackRequested: ackRequested,
          chunk: Uint8List.sublistView(
            envelope,
            i * maxChunk,
            (i + 1) * maxChunk < envelope.length
                ? (i + 1) * maxChunk
                : envelope.length,
          ),
        ),
    ];
  }
}

enum FragmentStatus {
  /// New fragment stored; message still incomplete.
  accepted,

  /// Fragment already held (or message already delivered): nothing changed.
  duplicate,

  /// This fragment completed a message; see [FragmentResult.message].
  completed,

  /// Fragment discarded (not DATA, inconsistent, or limits exceeded).
  rejected,
}

class FragmentResult {
  final FragmentStatus status;
  final int received;
  final int count;
  final LinkMessage? message;
  final String? error;

  const FragmentResult(this.status, this.received, this.count,
      {this.message, this.error});
}

class ReassemblyFailure {
  final int src;
  final int msgId;
  final int received;
  final int count;
  final String reason;

  const ReassemblyFailure(
      this.src, this.msgId, this.received, this.count, this.reason);

  @override
  String toString() =>
      'Reassembly of message $msgId from $src failed after $received/$count '
      'fragments: $reason';
}

/// One message being reassembled.
class ReassemblySession {
  final int src;
  final int msgId;
  final int count;
  final bool ackRequested;
  final Map<int, Uint8List> _chunks = {};
  int _bytes = 0;
  DateTime lastUpdate;

  ReassemblySession._(
      this.src, this.msgId, this.count, this.ackRequested, this.lastUpdate);

  int get received => _chunks.length;

  /// Lowest fragment index not yet received.
  int get lowestMissing {
    for (var i = 0; i < count; i++) {
      if (!_chunks.containsKey(i)) return i;
    }
    return count;
  }
}

class PayloadReassembler {
  /// Idle time after which an incomplete message is abandoned. Mutable so
  /// the RX engine can scale it with the current frame airtime.
  Duration timeout;

  /// Concurrent incomplete messages kept; the least recently updated one is
  /// evicted beyond this.
  final int maxSessions;

  /// Upper bound on a buffered envelope (content limit + header room).
  final int maxEnvelopeBytes;

  /// How long delivered message ids are remembered to suppress duplicates.
  final Duration completedRetention;

  final Map<int, ReassemblySession> _sessions = {};
  final LinkedHashMap<int, DateTime> _completed = LinkedHashMap();
  final List<ReassemblyFailure> _failures = [];

  static const int _completedCap = 256;

  PayloadReassembler({
    this.timeout = const Duration(seconds: 30),
    this.maxSessions = 8,
    this.maxEnvelopeBytes = LinkMessage.maxContentBytes + 1024,
    this.completedRetention = const Duration(minutes: 10),
  });

  static int _key(int src, int msgId) => (src << 16) | msgId;

  Iterable<ReassemblySession> get sessions => _sessions.values;

  /// Earliest time at which [expire] has something to do, if any.
  DateTime? get nextDeadline {
    DateTime? t;
    for (final s in _sessions.values) {
      final d = s.lastUpdate.add(timeout);
      if (t == null || d.isBefore(t)) t = d;
    }
    return t;
  }

  FragmentResult add(LinkFrame f, DateTime now) {
    if (f.type != LinkFrameType.data) {
      return const FragmentResult(FragmentStatus.rejected, 0, 0,
          error: 'not a DATA frame');
    }
    final key = _key(f.src, f.msgId);
    _pruneCompleted(now);
    if (_completed.containsKey(key)) {
      return FragmentResult(FragmentStatus.duplicate, f.count, f.count);
    }

    var s = _sessions[key];
    if (s != null && s.count != f.count) {
      // Same id, different shape: the sender restarted and reused the id.
      _fail(s, 'superseded by a new message with the same id');
      s = null;
    }
    if (s == null) {
      if (_sessions.length >= maxSessions) {
        final oldest = _sessions.values
            .reduce((a, b) => a.lastUpdate.isBefore(b.lastUpdate) ? a : b);
        _fail(oldest, 'evicted: too many concurrent transfers');
      }
      s = ReassemblySession._(f.src, f.msgId, f.count, f.ackRequested, now);
      _sessions[key] = s;
    }
    s.lastUpdate = now;

    if (s._chunks.containsKey(f.index)) {
      return FragmentResult(FragmentStatus.duplicate, s.received, s.count);
    }
    if (s._bytes + f.chunk.length > maxEnvelopeBytes) {
      _fail(s, 'message exceeds $maxEnvelopeBytes bytes');
      return FragmentResult(FragmentStatus.rejected, s.received, s.count,
          error: 'message too large');
    }
    s._chunks[f.index] = f.chunk;
    s._bytes += f.chunk.length;
    if (s.received < s.count) {
      return FragmentResult(FragmentStatus.accepted, s.received, s.count);
    }

    _sessions.remove(key);
    final envelope = BytesBuilder(copy: false);
    for (var i = 0; i < s.count; i++) {
      envelope.add(s._chunks[i]!);
    }
    try {
      final message = LinkMessage.decode(envelope.takeBytes());
      _completed[key] = now;
      while (_completed.length > _completedCap) {
        _completed.remove(_completed.keys.first);
      }
      return FragmentResult(FragmentStatus.completed, s.count, s.count,
          message: message);
    } on FormatException catch (e) {
      _failures.add(ReassemblyFailure(
          s.src, s.msgId, s.received, s.count, 'corrupt: ${e.message}'));
      return FragmentResult(FragmentStatus.rejected, s.received, s.count,
          error: e.message);
    }
  }

  /// Drops sessions idle for longer than [timeout] and returns every failure
  /// (timeouts, evictions, corrupt messages) since the last call.
  List<ReassemblyFailure> expire(DateTime now) {
    final stale = [
      for (final s in _sessions.values)
        if (now.difference(s.lastUpdate) >= timeout) s,
    ];
    for (final s in stale) {
      _fail(s, 'timed out after ${timeout.inMilliseconds} ms idle');
    }
    final out = List<ReassemblyFailure>.of(_failures);
    _failures.clear();
    return out;
  }

  void clear() {
    _sessions.clear();
    _failures.clear();
  }

  void _fail(ReassemblySession s, String reason) {
    _sessions.remove(_key(s.src, s.msgId));
    _failures
        .add(ReassemblyFailure(s.src, s.msgId, s.received, s.count, reason));
  }

  void _pruneCompleted(DateTime now) {
    _completed.removeWhere((_, t) => now.difference(t) > completedRetention);
  }
}
