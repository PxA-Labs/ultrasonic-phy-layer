// Signal metrics data models and modem link state definitions.
// Follows OpenSSF secure coding guidelines with robust bounds clamping and null safety.

import 'package:flutter/foundation.dart';

/// Connection and modem link state.
enum ModemLinkState {
  idle,
  listening,
  transmitting,
  receiving,
  error,
}

/// Metric event emitted after payload transmission.
@immutable
class TxMetrics {
  final int bytesSent;
  final DateTime timestamp;

  const TxMetrics({
    required this.bytesSent,
    required this.timestamp,
  });

  @override
  String toString() =>
      'TxMetrics(bytesSent: $bytesSent, timestamp: $timestamp)';
}

/// Event emitted during RX frame lifecycle (detection, decoding, or CRC failure).
@immutable
class RxFrameEvent {
  final bool detected;
  final bool decoded;
  final double snr;
  final int byteLength;
  final DateTime timestamp;
  final String? errorMessage;

  const RxFrameEvent({
    required this.detected,
    required this.decoded,
    required this.snr,
    required this.byteLength,
    required this.timestamp,
    this.errorMessage,
  });

  @override
  String toString() =>
      'RxFrameEvent(detected: $detected, decoded: $decoded, snr: $snr dB, byteLength: $byteLength)';
}

/// Real-time composite signal and link quality metrics.
@immutable
class SignalMetrics {
  final ModemLinkState connectionState;
  final double snr; // in dB [0.0 - 60.0]
  final double bitsPerSecond; // Instantaneous / rolling throughput in bps
  final int totalBytesTransferred;
  final int framesReceived;
  final int framesDetected;
  final int frameErrors;
  final DateTime lastUpdated;

  SignalMetrics({
    this.connectionState = ModemLinkState.idle,
    double snr = 0.0,
    double bitsPerSecond = 0.0,
    this.totalBytesTransferred = 0,
    this.framesReceived = 0,
    this.framesDetected = 0,
    this.frameErrors = 0,
    DateTime? lastUpdated,
  })  : snr = snr.clamp(0.0,
            60.0), // OpenSSF secure bounds check: SNR clamped to physical bounds
        bitsPerSecond =
            bitsPerSecond.clamp(0.0, 10000000.0), // OpenSSF secure bounds check
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Calculates frame success rate as a normalized ratio [0.0 - 1.0].
  double get frameSuccessRate {
    if (framesDetected <= 0) return 1.0;
    final rate = framesReceived / framesDetected;
    return rate.clamp(0.0, 1.0);
  }

  /// Human-readable formatted throughput string (e.g., '1.2 kbps', '450 bps', or '--- bps').
  String get formattedThroughput {
    if (bitsPerSecond <= 0.0) return '--- bps';
    if (bitsPerSecond >= 1000.0) {
      return '${(bitsPerSecond / 1000.0).toStringAsFixed(1)} kbps';
    }
    return '${bitsPerSecond.toStringAsFixed(0)} bps';
  }

  /// Human-readable formatted SNR string (e.g., '14.2 dB' or '--- dB').
  String get formattedSnr {
    if (snr <= 0.0) return '--- dB';
    return '${snr.toStringAsFixed(1)} dB';
  }

  /// Human-readable connection status label.
  String get statusLabel {
    switch (connectionState) {
      case ModemLinkState.idle:
        return 'Idle';
      case ModemLinkState.listening:
        return 'Listening…';
      case ModemLinkState.transmitting:
        return 'Transmitting…';
      case ModemLinkState.receiving:
        return 'Receiving Frame…';
      case ModemLinkState.error:
        return 'Error / CRC Failure';
    }
  }

  /// Creates a copy of [SignalMetrics] with optional field overrides.
  SignalMetrics copyWith({
    ModemLinkState? connectionState,
    double? snr,
    double? bitsPerSecond,
    int? totalBytesTransferred,
    int? framesReceived,
    int? framesDetected,
    int? frameErrors,
    DateTime? lastUpdated,
  }) {
    return SignalMetrics(
      connectionState: connectionState ?? this.connectionState,
      snr: snr ?? this.snr,
      bitsPerSecond: bitsPerSecond ?? this.bitsPerSecond,
      totalBytesTransferred:
          totalBytesTransferred ?? this.totalBytesTransferred,
      framesReceived: framesReceived ?? this.framesReceived,
      framesDetected: framesDetected ?? this.framesDetected,
      frameErrors: frameErrors ?? this.frameErrors,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  String toString() {
    return 'SignalMetrics(state: $connectionState, snr: $formattedSnr, throughput: $formattedThroughput, frames: $framesReceived/$framesDetected, errors: $frameErrors)';
  }
}
