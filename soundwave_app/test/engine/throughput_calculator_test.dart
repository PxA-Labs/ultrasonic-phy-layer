// Unit tests for ThroughputCalculator rolling 5-second window calculation

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/throughput_calculator.dart';

void main() {
  group('ThroughputCalculator', () {
    test('initial throughput is 0.0 bps', () {
      final calc = ThroughputCalculator();
      expect(calc.calculateBitsPerSecond(), 0.0);
      expect(calc.sampleCount, 0);
    });

    test('ignores non-positive byte transfers', () {
      final calc = ThroughputCalculator();
      calc.recordTransfer(0);
      calc.recordTransfer(-10);
      expect(calc.sampleCount, 0);
      expect(calc.calculateBitsPerSecond(), 0.0);
    });

    test('calculates correct throughput for known byte counts and timestamps',
        () {
      // 5-second window. 1250 bytes transferred = 10,000 bits / 5s = 2000 bps
      final calc = ThroughputCalculator(
        windowDuration: const Duration(seconds: 5),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      calc.recordTransfer(1250, t0);

      // Instantaneous throughput evaluated at t0 + 1s (still within 5s window)
      final rate =
          calc.calculateBitsPerSecond(t0.add(const Duration(seconds: 1)));
      expect(rate, closeTo(2000.0, 0.01));
    });

    test('accumulates multiple transfers in window', () {
      final calc = ThroughputCalculator(
        windowDuration: const Duration(seconds: 5),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // Transfer 1: 500 bytes (4000 bits) at t0
      calc.recordTransfer(500, t0);
      // Transfer 2: 750 bytes (6000 bits) at t0 + 2s
      calc.recordTransfer(750, t0.add(const Duration(seconds: 2)));

      // At t0 + 3s, total = 1250 bytes = 10,000 bits / 5s = 2000 bps
      final rate =
          calc.calculateBitsPerSecond(t0.add(const Duration(seconds: 3)));
      expect(rate, closeTo(2000.0, 0.01));
      expect(calc.sampleCount, 2);
    });

    test('prunes samples older than window duration', () {
      final calc = ThroughputCalculator(
        windowDuration: const Duration(seconds: 5),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // Transfer 1 at t0
      calc.recordTransfer(500, t0);
      // Transfer 2 at t0 + 4s
      calc.recordTransfer(500, t0.add(const Duration(seconds: 4)));

      // At t0 + 6s: Transfer 1 (at t0) is pruned because cutoff is t0 + 1s
      // Remaining = 500 bytes = 4000 bits / 5s = 800 bps
      final rate =
          calc.calculateBitsPerSecond(t0.add(const Duration(seconds: 6)));
      expect(rate, closeTo(800.0, 0.01));
      expect(calc.sampleCount, 1);

      // At t0 + 10s: Transfer 2 is also pruned
      final rateAfter =
          calc.calculateBitsPerSecond(t0.add(const Duration(seconds: 10)));
      expect(rateAfter, 0.0);
      expect(calc.sampleCount, 0);
    });

    test('reset clears all samples', () {
      final calc = ThroughputCalculator();
      calc.recordTransfer(100);
      calc.recordTransfer(200);
      expect(calc.sampleCount, 2);

      calc.reset();
      expect(calc.sampleCount, 0);
      expect(calc.calculateBitsPerSecond(), 0.0);
    });
  });
}
