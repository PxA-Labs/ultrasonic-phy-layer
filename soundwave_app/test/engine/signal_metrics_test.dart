// Unit tests for SignalMetrics model and ModemLinkState

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/signal_metrics.dart';

void main() {
  group('SignalMetrics', () {
    test('default values', () {
      final now = DateTime.now();
      final metrics = SignalMetrics(lastUpdated: now);

      expect(metrics.connectionState, ModemLinkState.idle);
      expect(metrics.snr, 0.0);
      expect(metrics.bitsPerSecond, 0.0);
      expect(metrics.totalBytesTransferred, 0);
      expect(metrics.framesReceived, 0);
      expect(metrics.framesDetected, 0);
      expect(metrics.frameErrors, 0);
      expect(metrics.frameSuccessRate, 1.0);
      expect(metrics.formattedThroughput, '--- bps');
      expect(metrics.formattedSnr, '--- dB');
      expect(metrics.statusLabel, 'Idle');
    });

    test('OpenSSF secure bounds clamping', () {
      final metrics = SignalMetrics(
        snr: -10.0,
        bitsPerSecond: -50.0,
      );
      expect(metrics.snr, 0.0);
      expect(metrics.bitsPerSecond, 0.0);

      final metricsHigh = SignalMetrics(
        snr: 120.0,
        bitsPerSecond: 99999999.0,
      );
      expect(metricsHigh.snr, 60.0);
      expect(metricsHigh.bitsPerSecond, 10000000.0);
    });

    test('frameSuccessRate calculation', () {
      final m1 = SignalMetrics(
        framesDetected: 10,
        framesReceived: 8,
      );
      expect(m1.frameSuccessRate, closeTo(0.8, 0.001));

      final mZero = SignalMetrics(
        framesDetected: 0,
        framesReceived: 0,
      );
      expect(mZero.frameSuccessRate, 1.0);
    });

    test('formattedThroughput output', () {
      expect(SignalMetrics(bitsPerSecond: 0.0).formattedThroughput, '--- bps');
      expect(
          SignalMetrics(bitsPerSecond: 450.0).formattedThroughput, '450 bps');
      expect(
          SignalMetrics(bitsPerSecond: 1200.0).formattedThroughput, '1.2 kbps');
      expect(SignalMetrics(bitsPerSecond: 15400.0).formattedThroughput,
          '15.4 kbps');
    });

    test('formattedSnr output', () {
      expect(SignalMetrics(snr: 0.0).formattedSnr, '--- dB');
      expect(SignalMetrics(snr: 14.25).formattedSnr, '14.3 dB');
      expect(SignalMetrics(snr: 8.0).formattedSnr, '8.0 dB');
    });

    test('statusLabel matches connection states', () {
      expect(SignalMetrics(connectionState: ModemLinkState.idle).statusLabel,
          'Idle');
      expect(
          SignalMetrics(connectionState: ModemLinkState.listening).statusLabel,
          'Listening…');
      expect(
          SignalMetrics(connectionState: ModemLinkState.transmitting)
              .statusLabel,
          'Transmitting…');
      expect(
          SignalMetrics(connectionState: ModemLinkState.receiving).statusLabel,
          'Receiving Frame…');
      expect(SignalMetrics(connectionState: ModemLinkState.error).statusLabel,
          'Error / CRC Failure');
    });

    test('copyWith modifies targeted fields only', () {
      final now = DateTime.now();
      final original = SignalMetrics(
        connectionState: ModemLinkState.idle,
        snr: 12.0,
        bitsPerSecond: 500.0,
        totalBytesTransferred: 100,
        framesReceived: 2,
        framesDetected: 2,
        frameErrors: 0,
        lastUpdated: now,
      );

      final updated = original.copyWith(
        connectionState: ModemLinkState.receiving,
        snr: 18.5,
        framesReceived: 3,
        framesDetected: 3,
      );

      expect(updated.connectionState, ModemLinkState.receiving);
      expect(updated.snr, 18.5);
      expect(updated.bitsPerSecond, 500.0);
      expect(updated.totalBytesTransferred, 100);
      expect(updated.framesReceived, 3);
      expect(updated.framesDetected, 3);
      expect(updated.frameErrors, 0);
    });

    test('TxMetrics and RxFrameEvent string representations', () {
      final tx = TxMetrics(bytesSent: 64, timestamp: DateTime.now());
      expect(tx.bytesSent, 64);
      expect(tx.toString(), contains('bytesSent: 64'));

      final rx = RxFrameEvent(
        detected: true,
        decoded: true,
        snr: 15.2,
        byteLength: 48,
        timestamp: DateTime.now(),
      );
      expect(rx.detected, true);
      expect(rx.decoded, true);
      expect(rx.toString(), contains('15.2 dB'));
    });
  });
}
