// Throughput calculator maintaining a rolling time window of transmitted/received bytes.
// OpenSSF compliance: bounded memory footprint, non-negative rate clamps, safe division.

import 'dart:math' as math;

/// Single byte transfer sample timestamp.
class TransferSample {
  final int bytes;
  final DateTime timestamp;

  const TransferSample({
    required this.bytes,
    required this.timestamp,
  });
}

/// Rolling time-window throughput calculator.
class ThroughputCalculator {
  final Duration windowDuration;
  final List<TransferSample> _samples = [];
  static const int _maxSamples = 1000; // OpenSSF bounded memory buffer limit

  ThroughputCalculator({
    this.windowDuration = const Duration(seconds: 5),
  });

  /// Records a byte transfer of [bytes] at [timestamp] (or now).
  void recordTransfer(int bytes, [DateTime? timestamp]) {
    if (bytes <= 0) return;
    final now = timestamp ?? DateTime.now();

    _samples.add(TransferSample(bytes: bytes, timestamp: now));

    // Prune stale samples
    _prune(now);

    // Safeguard max sample count to avoid unbounded memory growth
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _maxSamples);
    }
  }

  /// Calculates the rolling bits-per-second rate over [windowDuration].
  double calculateBitsPerSecond([DateTime? currentTimestamp]) {
    final now = currentTimestamp ?? DateTime.now();
    _prune(now);

    if (_samples.isEmpty) {
      return 0.0;
    }

    int totalBytes = 0;
    for (final sample in _samples) {
      totalBytes += sample.bytes;
    }

    final totalBits = totalBytes * 8;
    final windowSec = windowDuration.inMicroseconds / 1000000.0;
    if (windowSec <= 0.0) {
      return 0.0;
    }

    final bps = totalBits / windowSec;
    return math.max(0.0, bps);
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(windowDuration);
    _samples.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
  }

  /// Resets the throughput history.
  void reset() {
    _samples.clear();
  }

  /// Current sample count in window.
  int get sampleCount => _samples.length;
}
