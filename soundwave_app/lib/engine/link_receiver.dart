// Receive side of the link layer (#89, #100): routes decoded link frames to
// the reassembler, decides which ACK/NACK replies to send, and filters out
// this node's own transmissions (on an acoustic link the microphone hears the
// local speaker). Pure Dart; the RX engine supplies the clock.

import 'package:soundwave/engine/fragmentation.dart';
import 'package:soundwave/engine/link_frame.dart';

/// Progress of an incoming multi-fragment message.
enum RxTransferState { receiving, completed, failed }

class RxTransferProgress {
  final int src;
  final int msgId;
  final int received;
  final int count;
  final RxTransferState state;
  final String? error;

  const RxTransferProgress({
    required this.src,
    required this.msgId,
    required this.received,
    required this.count,
    required this.state,
    this.error,
  });

  double get fraction => count == 0 ? 0 : received / count;
}

class LinkRxOutcome {
  /// A fully reassembled, CRC-verified message.
  final LinkMessage? message;

  /// An ACK/NACK addressed to this node, for the local ARQ sender.
  final LinkFrame? control;

  /// A reply (ACK) this node should transmit.
  final LinkFrame? reply;

  final RxTransferProgress? progress;

  const LinkRxOutcome({this.message, this.control, this.reply, this.progress});

  static const LinkRxOutcome none = LinkRxOutcome();
}

class LinkReceiver {
  final int nodeId;
  final PayloadReassembler reassembler;

  /// Identical replies within this window are sent once (e.g. a frame decoded
  /// twice from an echo). A genuine retransmission arrives much later and is
  /// ACKed again, because it means the previous ACK was lost.
  final Duration replyDebounce;

  final Map<String, DateTime> _recentReplies = {};

  LinkReceiver({
    required this.nodeId,
    PayloadReassembler? reassembler,
    this.replyDebounce = const Duration(milliseconds: 150),
  }) : reassembler = reassembler ?? PayloadReassembler();

  /// Handles one decoded link frame. [arqEnabled] is the local setting: when
  /// off this node never transmits (pure listener / one-way broadcast).
  LinkRxOutcome handle(LinkFrame f, DateTime now, {required bool arqEnabled}) {
    if (f.src == nodeId) return LinkRxOutcome.none; // our own echo
    if (f.isControl) {
      return f.dst == nodeId ? LinkRxOutcome(control: f) : LinkRxOutcome.none;
    }

    final r = reassembler.add(f, now);
    final ack = arqEnabled &&
            f.ackRequested &&
            r.status != FragmentStatus.rejected
        ? _debounced(
            LinkFrame.ack(
                src: nodeId, dst: f.src, msgId: f.msgId, index: f.index),
            now)
        : null;
    final state = switch (r.status) {
      FragmentStatus.completed => RxTransferState.completed,
      FragmentStatus.rejected => RxTransferState.failed,
      _ => RxTransferState.receiving,
    };
    return LinkRxOutcome(
      message: r.message,
      reply: ack,
      progress: r.status == FragmentStatus.duplicate && r.received == r.count
          ? null // already delivered; nothing new to report
          : RxTransferProgress(
              src: f.src,
              msgId: f.msgId,
              received: r.received,
              count: r.count,
              state: state,
              error: r.error,
            ),
    );
  }

  /// Called when a frame was detected but failed CRC/RS. If exactly one
  /// ARQ transfer is in progress, NACK its lowest missing fragment so the
  /// sender retransmits without waiting for its ACK timeout. Otherwise the
  /// sender of the corrupted frame is unknown and its timeout handles it.
  LinkFrame? onFrameError(DateTime now, {required bool arqEnabled}) {
    if (!arqEnabled) return null;
    final active = [
      for (final s in reassembler.sessions)
        if (s.ackRequested && now.difference(s.lastUpdate) < reassembler.timeout)
          s,
    ];
    if (active.length != 1) return null;
    final s = active.single;
    return _debounced(
        LinkFrame.nack(
            src: nodeId, dst: s.src, msgId: s.msgId, index: s.lowestMissing),
        now);
  }

  LinkFrame? _debounced(LinkFrame reply, DateTime now) {
    _recentReplies
        .removeWhere((_, t) => now.difference(t) >= replyDebounce * 4);
    final key = '${reply.type.name}:${reply.dst}:${reply.msgId}:${reply.index}';
    final last = _recentReplies[key];
    if (last != null && now.difference(last) < replyDebounce) return null;
    _recentReplies[key] = now;
    return reply;
  }
}
