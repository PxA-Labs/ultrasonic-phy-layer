// Automatic retransmission (#100) — stop-and-wait ARQ over the half-duplex
// acoustic link.
//
// Each DATA fragment is sent and the sender waits for the matching ACK before
// sending the next one. Stop-and-wait suits this link: only one side can
// transmit at a time, a frame is long compared with the turnaround, and the
// receiver always knows exactly which fragment is outstanding (so a NACK on a
// CRC failure can name it). The wait after each transmission is
//
//   airtime(frame) + responseAllowance + ackTimeout * backoff^attempt (+jitter)
//
// where responseAllowance covers the ACK's own airtime and the receiver's
// decode latency. A NACK triggers an immediate retransmission. After
// maxRetries retransmissions of one fragment the transfer fails with
// [TxMaxRetriesError]. With ARQ disabled the same fragments are broadcast once,
// paced by their airtime, and nobody replies.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/link_frame.dart';

class ArqConfig {
  static const List<int> retryOptions = [1, 3, 5];
  static const int minAckTimeoutMs = 200, maxAckTimeoutMs = 2000;

  final bool enabled;
  final int maxRetries;
  final Duration ackTimeout;
  final double backoffFactor;

  /// Cap on the backed-off part of a single wait.
  final Duration maxBackoff;

  const ArqConfig({
    this.enabled = false,
    this.maxRetries = 3,
    this.ackTimeout = const Duration(milliseconds: 500),
    this.backoffFactor = 2.0,
    this.maxBackoff = const Duration(seconds: 30),
  });

  /// Reads `arq_enabled`, `arq_max_retries`, `arq_ack_timeout_ms` from the
  /// modem config map, falling back to defaults for missing/invalid values.
  factory ArqConfig.fromMap(Map<String, dynamic> cfg) {
    final retries = (cfg['arq_max_retries'] as num?)?.toInt();
    final timeout = (cfg['arq_ack_timeout_ms'] as num?)?.toInt();
    return ArqConfig(
      enabled: cfg['arq_enabled'] as bool? ?? false,
      maxRetries:
          retries != null && retries >= 0 && retries <= 16 ? retries : 3,
      ackTimeout: Duration(
          milliseconds: timeout != null &&
                  timeout >= minAckTimeoutMs &&
                  timeout <= maxAckTimeoutMs
              ? timeout
              : 500),
    );
  }

  /// Backed-off timeout for the given attempt (0 = first transmission).
  Duration backoffFor(int attempt) {
    final ms = ackTimeout.inMicroseconds * math.pow(backoffFactor, attempt);
    final capped = math.min(ms, maxBackoff.inMicroseconds.toDouble());
    return Duration(microseconds: capped.round());
  }
}

class TxMaxRetriesError implements Exception {
  final int msgId;
  final int fragmentIndex;
  final int attempts;

  const TxMaxRetriesError(this.msgId, this.fragmentIndex, this.attempts);

  @override
  String toString() => 'TxMaxRetriesError: fragment ${fragmentIndex + 1} of '
      'message $msgId not acknowledged after $attempts transmissions';
}

class TransferCancelledError implements Exception {
  const TransferCancelledError();

  @override
  String toString() => 'TransferCancelledError: transfer cancelled';
}

enum TxTransferState { sending, retrying, completed, failed, cancelled }

class TxTransferProgress {
  final int msgId;

  /// Fragments delivered (ARQ: acknowledged; broadcast: transmitted).
  final int fragmentsDone;
  final int fragmentCount;
  final int retransmissions;
  final TxTransferState state;
  final String? fileName;
  final int contentBytes;
  final String? error;

  /// Time since the transfer started (first fragment handed to the PHY);
  /// for [TxTransferState.completed], the whole transfer including the
  /// final ACK wait.
  final Duration elapsed;

  const TxTransferProgress({
    required this.msgId,
    required this.fragmentsDone,
    required this.fragmentCount,
    required this.retransmissions,
    required this.state,
    required this.contentBytes,
    this.fileName,
    this.error,
    this.elapsed = Duration.zero,
  });

  double get fraction => fragmentCount == 0 ? 0 : fragmentsDone / fragmentCount;
}

enum _Reply { ack, nack, timeout, cancelled }

class _Wait {
  final int msgId;
  final int index;
  final bool acceptReplies;
  final Completer<_Reply> completer = Completer<_Reply>();

  _Wait(this.msgId, this.index, {required this.acceptReplies});

  void complete(_Reply r) {
    if (!completer.isCompleted) completer.complete(r);
  }
}

class ArqSender {
  final int nodeId;

  /// Transmits one PHY payload and returns its airtime. Playback is
  /// asynchronous, so the sender itself waits out the airtime.
  final Future<Duration> Function(Uint8List payload) transmit;

  /// Time for the peer's reply to arrive once our frame has ended: ACK
  /// airtime plus receiver decode latency.
  final Duration Function() responseAllowance;

  final math.Random _random;

  /// Clock for transfer timing (injectable for tests).
  final DateTime Function() _now;

  final StreamController<TxTransferProgress> _progress =
      StreamController<TxTransferProgress>.broadcast();

  int _nextMsgId;
  _Wait? _wait;
  bool _cancelRequested = false;
  Future<void> _tail = Future<void>.value();

  int _retransmissions = 0;
  int _duplicateReplies = 0;

  ArqSender({
    required this.nodeId,
    required this.transmit,
    Duration Function()? responseAllowance,
    math.Random? random,
    DateTime Function()? now,
  })  : responseAllowance = responseAllowance ?? (() => Duration.zero),
        _now = now ?? DateTime.now,
        _random = random ?? math.Random(),
        _nextMsgId = (random ?? math.Random()).nextInt(0x10000);

  Stream<TxTransferProgress> get progress => _progress.stream;

  /// Total retransmissions since creation.
  int get retransmissions => _retransmissions;

  /// ACK/NACKs that matched nothing outstanding (late or duplicated).
  int get duplicateReplies => _duplicateReplies;

  /// Sends [message], fragmenting as needed. Concurrent calls are serialised.
  /// Throws [TxMaxRetriesError] or [TransferCancelledError] on failure.
  Future<void> send(LinkMessage message, ArqConfig config,
      {int maxChunk = LinkFrame.maxChunk}) {
    final run = _tail.then((_) => _send(message, config, maxChunk));
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Aborts the transfer in progress (if any).
  void cancel() {
    _cancelRequested = true;
    _wait?.complete(_Reply.cancelled);
  }

  /// Feeds an ACK/NACK addressed to this node (from the RX engine).
  void onControlFrame(LinkFrame f) {
    if (!f.isControl || f.dst != nodeId) return;
    final w = _wait;
    if (w == null ||
        !w.acceptReplies ||
        w.completer.isCompleted ||
        w.msgId != f.msgId ||
        w.index != f.index) {
      _duplicateReplies++;
      return;
    }
    w.complete(f.type == LinkFrameType.ack ? _Reply.ack : _Reply.nack);
  }

  Future<void> _send(
      LinkMessage message, ArqConfig config, int maxChunk) async {
    _cancelRequested = false;
    final msgId = _nextMsgId;
    _nextMsgId = (_nextMsgId + 1) & 0xFFFF;
    final frames = PayloadFragmenter(maxChunk: maxChunk).fragment(message,
        src: nodeId, msgId: msgId, ackRequested: config.enabled);
    var retries = 0;
    final started = _now();

    void emit(int done, TxTransferState state, [String? error]) {
      if (_progress.isClosed) return;
      _progress.add(TxTransferProgress(
        msgId: msgId,
        fragmentsDone: done,
        fragmentCount: frames.length,
        retransmissions: retries,
        state: state,
        fileName: message.fileName,
        contentBytes: message.content.length,
        error: error,
        elapsed: _now().difference(started),
      ));
    }

    emit(0, TxTransferState.sending);
    for (var i = 0; i < frames.length; i++) {
      final payload = frames[i].encode();
      for (var attempt = 0;; attempt++) {
        if (_cancelRequested) {
          emit(i, TxTransferState.cancelled);
          throw const TransferCancelledError();
        }
        // Register before transmitting so an immediate reply is not missed.
        final wait = _Wait(msgId, i, acceptReplies: config.enabled);
        _wait = wait;
        final airtime = await transmit(payload);
        final Duration window;
        if (config.enabled) {
          final jitterUs = config.ackTimeout.inMicroseconds ~/ 10;
          window = airtime +
              responseAllowance() +
              config.backoffFor(attempt) +
              Duration(
                  microseconds: jitterUs > 0 ? _random.nextInt(jitterUs) : 0);
        } else {
          window = airtime;
        }
        final reply = await _await(wait, window);
        if (reply == _Reply.cancelled) {
          emit(i, TxTransferState.cancelled);
          throw const TransferCancelledError();
        }
        if (!config.enabled || reply == _Reply.ack) break;

        if (attempt >= config.maxRetries) {
          final err = TxMaxRetriesError(msgId, i, attempt + 1);
          emit(i, TxTransferState.failed, err.toString());
          throw err;
        }
        retries++;
        _retransmissions++;
        emit(i, TxTransferState.retrying);
      }
      emit(i + 1, TxTransferState.sending);
    }
    emit(frames.length, TxTransferState.completed);
  }

  Future<_Reply> _await(_Wait wait, Duration window) async {
    final timer = Timer(window, () => wait.complete(_Reply.timeout));
    try {
      return await wait.completer.future;
    } finally {
      timer.cancel();
      if (identical(_wait, wait)) _wait = null;
    }
  }

  void dispose() {
    cancel();
    _progress.close();
  }
}
