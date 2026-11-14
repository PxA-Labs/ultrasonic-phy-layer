// Screen-reader summary of the ultrasonic band (issue #93): is a signal
// present in 18-22 kHz, where, and how strong. The spectrum and waterfall
// are pictures; this turns them into a short sentence that changes only when
// a signal starts or stops, so a live region announces transitions instead
// of reading out every frame.

import 'dart:typed_data';

class BandActivity {
  final bool active;

  /// Peak frequency and level when [active] became true.
  final double peakHz;
  final double peakDb;

  const BandActivity.quiet()
      : active = false,
        peakHz = 0,
        peakDb = double.negativeInfinity;

  const BandActivity.signal(this.peakHz, this.peakDb) : active = true;

  /// e.g. "Ultrasonic signal at 19.0 kHz, -15 dBFS" / "No ultrasonic signal".
  String describe() => active
      ? 'Ultrasonic signal at ${(peakHz / 1000).toStringAsFixed(1)} kHz, '
          '${peakDb.round()} dBFS'
      : 'No ultrasonic signal';

  @override
  bool operator ==(Object other) =>
      other is BandActivity &&
      other.active == active &&
      other.peakHz == peakHz &&
      other.peakDb == peakDb;

  @override
  int get hashCode => Object.hash(active, peakHz, peakDb);

  @override
  String toString() => 'BandActivity(${describe()})';
}

/// Tracks [BandActivity] from successive dBFS spectra with hysteresis: a
/// signal starts when the band peak reaches [onDb] and ends only after the
/// peak has stayed below [offDb] for [holdSeconds], so the gaps between
/// chirps or frames do not make it flap.
class BandActivityDetector {
  final double lowHz;
  final double highHz;
  final double onDb;
  final double offDb;
  final double holdSeconds;

  BandActivity _state = const BandActivity.quiet();
  double _quietFor = 0;

  BandActivityDetector({
    this.lowHz = 18000,
    this.highHz = 22000,
    this.onDb = -60,
    this.offDb = -70,
    this.holdSeconds = 1.0,
  }) {
    if (!(offDb <= onDb)) {
      throw ArgumentError('offDb ($offDb) must not exceed onDb ($onDb)');
    }
    if (!(highHz > lowHz)) {
      throw ArgumentError('highHz must be greater than lowHz');
    }
  }

  BandActivity get state => _state;

  void reset() {
    _state = const BandActivity.quiet();
    _quietFor = 0;
  }

  /// Folds in one spectrum observed [dtSeconds] after the previous one.
  /// Returns true when [state] changed (a start or an end).
  bool update(Float64List spectrumDb, double binWidthHz, double dtSeconds) {
    if (spectrumDb.isEmpty || !(binWidthHz > 0)) return false;
    final lo = (lowHz / binWidthHz).ceil().clamp(0, spectrumDb.length - 1);
    final hi = (highHz / binWidthHz).floor().clamp(0, spectrumDb.length - 1);
    var peak = lo;
    for (var k = lo + 1; k <= hi; k++) {
      if (spectrumDb[k] > spectrumDb[peak]) peak = k;
    }
    final level = spectrumDb[peak];
    final dt = dtSeconds.isFinite && dtSeconds > 0 ? dtSeconds : 0.0;

    if (!_state.active) {
      if (level >= onDb) {
        _state = BandActivity.signal(peak * binWidthHz, level);
        _quietFor = 0;
        return true;
      }
      return false;
    }
    if (level >= offDb) {
      _quietFor = 0;
      return false;
    }
    _quietFor += dt;
    if (_quietFor >= holdSeconds) {
      _state = const BandActivity.quiet();
      _quietFor = 0;
      return true;
    }
    return false;
  }
}
