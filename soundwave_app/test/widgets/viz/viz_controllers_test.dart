// FrameThrottle, colour maps and WaterfallController pixel logic (#91).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/widgets/viz/colormap.dart';
import 'package:soundwave/widgets/viz/constellation_widget.dart';
import 'package:soundwave/dsp/constellation.dart';
import 'package:soundwave/widgets/viz/frame_throttle.dart';
import 'package:soundwave/widgets/viz/waterfall_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameThrottle', () {
    test('fires immediately, then coalesces requests into one deferred call',
        () async {
      var now = Duration.zero;
      var fired = 0;
      final t = FrameThrottle(
        interval: const Duration(milliseconds: 20),
        onFire: () => fired++,
        clock: () => now,
      );
      t.request();
      expect(fired, 1);
      expect(t.hasPending, isFalse);
      t.request();
      t.request();
      t.request();
      expect(fired, 1);
      expect(t.hasPending, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, 2);
      expect(t.hasPending, isFalse);
      // Once the interval has passed on the clock, a request fires at once.
      now = const Duration(seconds: 1);
      t.request();
      expect(fired, 3);
      t.dispose();
    });

    test('dispose cancels a pending call', () async {
      var fired = 0;
      final t = FrameThrottle(
        interval: const Duration(milliseconds: 20),
        onFire: () => fired++,
        clock: () => Duration.zero,
      );
      t.request();
      t.request();
      t.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, 1);
      t.request();
      expect(fired, 1);
    });
  });

  group('WaterfallColormap', () {
    test('LUT endpoints follow the palette stops', () {
      final v = WaterfallColormap.viridis.rgbaLut;
      expect(v.length, 1024);
      expect(v.sublist(0, 4), [0x44, 0x01, 0x54, 0xFF]);
      expect(v.sublist(1020), [0xFD, 0xE7, 0x25, 0xFF]);
      final g = WaterfallColormap.grayscale.rgbaLut;
      expect(g.sublist(512, 516), [128, 128, 128, 255]);
    });

    test('indexOf clamps and handles NaN', () {
      expect(WaterfallColormap.indexOf(-1), 0);
      expect(WaterfallColormap.indexOf(double.nan), 0);
      expect(WaterfallColormap.indexOf(0.5), 128);
      expect(WaterfallColormap.indexOf(2), 255);
      expect(WaterfallColormap.thermal.colorAt(1).toARGB32(), 0xFFFFFFFF);
    });
  });

  group('WaterfallController', () {
    WaterfallController make() => WaterfallController(
          rows: 4,
          binCount: 3,
          binWidthHz: 100,
          secondsPerRow: 0.1,
          minDb: -100,
          maxDb: 0,
          colormap: WaterfallColormap.grayscale,
          frameInterval: const Duration(hours: 1),
        );

    test('pixels: newest row at the bottom, unfilled rows transparent', () {
      final c = make();
      c.addRow([-100, -50, 0]);
      c.addRow([0, 0, 0]);
      final px = c.buildPixels();
      expect(px.length, 4 * 3 * 4);
      // Rows 0 and 1 (oldest slots) are still empty.
      expect(px.sublist(0, 24).every((b) => b == 0), isTrue);
      // Row 2: the first row pushed.
      expect(px.sublist(24, 28), [0, 0, 0, 255]);
      expect(px.sublist(28, 32), [128, 128, 128, 255]);
      expect(px.sublist(32, 36), [255, 255, 255, 255]);
      // Row 3 (bottom): the newest row, all white.
      expect(px.sublist(36, 48).every((b) => b == 255), isTrue);
      c.dispose();
    });

    test('dB range and colour map changes re-colour stored rows', () {
      final c = make();
      c.addRow([-50, -50, -50]);
      expect(c.buildPixels().sublist(36, 40), [128, 128, 128, 255]);
      c.setDbRange(-50, 0);
      expect(c.buildPixels().sublist(36, 40), [0, 0, 0, 255]);
      c.setColormap(WaterfallColormap.viridis);
      expect(c.buildPixels().sublist(36, 40), [0x44, 0x01, 0x54, 255]);
      // Invalid ranges are ignored.
      c.setDbRange(0, -10);
      expect(c.minDb, -50);
      c.dispose();
    });

    test('pause freezes the history; valueAt reads it', () {
      final c = make();
      var notified = 0;
      c.addListener(() => notified++);
      c.addRow([-10, -20, -30]);
      c.togglePause();
      expect(c.paused, isTrue);
      expect(notified, greaterThan(0));
      c.addRow([0, 0, 0]);
      expect(c.buffer.length, 1);
      expect(c.valueAt(100, 0), -20);
      expect(c.valueAt(240, 0), -30);
      expect(c.valueAt(1000, 0), isNull);
      expect(c.valueAt(0, 1), isNull);
      c.setPaused(false);
      c.addRow([0, 0, 0]);
      expect(c.buffer.length, 2);
      expect(c.nyquistHz, 200);
      c.dispose();
    });

    test('ranges are clamped to the available band', () {
      expect(WaterfallRange.ultrasonic.bounds(19000, 22050), (18000, 22000));
      expect(WaterfallRange.carrier.bounds(19000, 22050), (18500, 19500));
      expect(WaterfallRange.full.bounds(19000, 22050), (0, 22050));
      expect(WaterfallRange.ultrasonic.bounds(19000, 11025), (11024, 11025));
    });
  });

  group('ConstellationController', () {
    ConstellationFrame frame(int points, ConstellationScheme scheme) =>
        ConstellationFrame(
          iq: Float32List(2 * points),
          scheme: scheme,
          decoded: true,
        );

    test('keeps the newest frames up to maxPoints', () {
      final c = ConstellationController(maxPoints: 10);
      c.addFrame(frame(4, ConstellationScheme.qpsk));
      c.addFrame(frame(4, ConstellationScheme.qpsk));
      expect(c.pointCount, 8);
      c.addFrame(frame(4, ConstellationScheme.qpsk));
      expect(c.frames, hasLength(2));
      expect(c.pointCount, 8);
      c.addFrame(frame(0, ConstellationScheme.qpsk)); // ignored
      expect(c.frames, hasLength(2));
    });

    test('a scheme change drops older frames', () {
      final c = ConstellationController();
      c.addFrame(frame(4, ConstellationScheme.qpsk));
      c.addFrame(frame(2, ConstellationScheme.bpsk));
      expect(c.frames, hasLength(1));
      expect(c.scheme, ConstellationScheme.bpsk);
      c.clear();
      expect(c.latest, isNull);
      expect(c.evm, isNull);
    });
  });
}
