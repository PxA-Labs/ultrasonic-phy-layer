// WaterfallBuffer ring-buffer behaviour (#91).

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/waterfall_buffer.dart';

List<double> row(double v, int bins) => List.filled(bins, v);

void main() {
  group('WaterfallBuffer', () {
    test('starts empty', () {
      final b = WaterfallBuffer(capacity: 3, binCount: 4);
      expect(b.isEmpty, isTrue);
      expect(b.length, 0);
      expect(b.totalPushed, 0);
      expect(() => b.rowAt(0), throwsRangeError);
    });

    test('age 0 is the newest row', () {
      final b = WaterfallBuffer(capacity: 3, binCount: 2);
      b.push([1, 10]);
      b.push([2, 20]);
      expect(b.length, 2);
      expect(b.rowAt(0), [2, 20]);
      expect(b.rowAt(1), [1, 10]);
      expect(b.valueAt(1, 1), 10);
      expect(() => b.rowAt(2), throwsRangeError);
    });

    test('evicts the oldest row once full and wraps around', () {
      final b = WaterfallBuffer(capacity: 3, binCount: 2);
      for (var i = 1; i <= 7; i++) {
        b.push(row(i.toDouble(), 2));
      }
      expect(b.length, 3);
      expect(b.totalPushed, 7);
      expect(b.rowAt(0), [7, 7]);
      expect(b.rowAt(1), [6, 6]);
      expect(b.rowAt(2), [5, 5]);
      // 7 pushes into 3 slots: the next write goes to slot 7 % 3 = 1.
      expect(b.writeSlot, 1);
      expect(b.slotOfAge(0), 0);
      expect(b.slotOfAge(2), 1);
    });

    test('rows are copied, not referenced', () {
      final b = WaterfallBuffer(capacity: 2, binCount: 2);
      final r = [1.0, 2.0];
      b.push(r);
      r[0] = 99;
      expect(b.rowAt(0), [1, 2]);
    });

    test('validates rows, bins and sizes', () {
      final b = WaterfallBuffer(capacity: 2, binCount: 3);
      expect(() => b.push([1, 2]), throwsArgumentError);
      b.push([1, 2, 3]);
      expect(() => b.valueAt(0, 3), throwsRangeError);
      expect(() => b.valueAt(-1, 0), throwsRangeError);
      expect(
        () => WaterfallBuffer(capacity: 0, binCount: 1),
        throwsArgumentError,
      );
      expect(
        () => WaterfallBuffer(capacity: 1, binCount: 0),
        throwsArgumentError,
      );
    });

    test('clear empties the buffer', () {
      final b = WaterfallBuffer(capacity: 2, binCount: 1);
      b.push([1]);
      b.push([2]);
      b.clear();
      expect(b.isEmpty, isTrue);
      expect(b.totalPushed, 0);
      b.push([3]);
      expect(b.rowAt(0), [3]);
      expect(b.length, 1);
    });
  });
}
