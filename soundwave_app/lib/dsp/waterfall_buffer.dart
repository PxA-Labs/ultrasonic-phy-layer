// Fixed-capacity ring buffer of spectrum rows for the waterfall (#91).

import 'dart:typed_data';

/// Holds the newest [capacity] spectra of [binCount] bins each in one flat
/// Float32List. Pushing is O(binCount) and never allocates.
class WaterfallBuffer {
  final int capacity;
  final int binCount;
  final Float32List _data;
  int _head = 0; // next row to write
  int _length = 0;
  int _totalPushed = 0;

  WaterfallBuffer({required this.capacity, required this.binCount})
      : _data = Float32List(_checkedSize(capacity, binCount));

  static int _checkedSize(int capacity, int binCount) {
    if (capacity <= 0 || binCount <= 0) {
      throw ArgumentError('capacity and binCount must be positive');
    }
    return capacity * binCount;
  }

  /// Rows currently stored (<= capacity).
  int get length => _length;

  bool get isEmpty => _length == 0;

  /// Rows pushed since creation or [clear], including overwritten ones.
  int get totalPushed => _totalPushed;

  /// Storage slot of the next row to be written; the slot of the row of
  /// age a is (writeSlot - 1 - a) mod capacity.
  int get writeSlot => _head;

  /// Appends [row] (exactly [binCount] values), evicting the oldest row
  /// when full.
  void push(List<double> row) {
    if (row.length != binCount) {
      throw ArgumentError('row must have $binCount bins, got ${row.length}');
    }
    final base = _head * binCount;
    for (var k = 0; k < binCount; k++) {
      _data[base + k] = row[k];
    }
    _head = (_head + 1) % capacity;
    if (_length < capacity) _length++;
    _totalPushed++;
  }

  /// Storage slot of the row of [age] (0 = newest).
  int slotOfAge(int age) {
    if (age < 0 || age >= _length) {
      throw RangeError.range(age, 0, _length - 1, 'age');
    }
    return (_head - 1 - age) % capacity;
  }

  /// View of the row of [age] (0 = newest). Valid until the next [push].
  Float32List rowAt(int age) {
    final slot = slotOfAge(age);
    return Float32List.sublistView(
      _data,
      slot * binCount,
      (slot + 1) * binCount,
    );
  }

  /// Value of [bin] in the row of [age] (0 = newest).
  double valueAt(int age, int bin) {
    if (bin < 0 || bin >= binCount) {
      throw RangeError.range(bin, 0, binCount - 1, 'bin');
    }
    return _data[slotOfAge(age) * binCount + bin];
  }

  void clear() {
    _head = 0;
    _length = 0;
    _totalPushed = 0;
  }
}
