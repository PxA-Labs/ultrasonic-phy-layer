// Rate limiter for visualizer repaints: audio arrives in bursts of chunks,
// but the plots only need to refresh at display-friendly rates (~30 fps).

import 'dart:async';

/// Calls [onFire] at most once per [interval]. A request inside the
/// interval is deferred (not dropped) to the end of the interval, and any
/// further requests until then coalesce into that one call.
class FrameThrottle {
  final Duration interval;
  final void Function() onFire;
  final Duration Function() _now;
  Duration? _lastFire;
  Timer? _timer;
  bool _disposed = false;

  FrameThrottle({
    required this.interval,
    required this.onFire,
    Duration Function()? clock,
  }) : _now = clock ?? _monotonicClock();

  static Duration Function() _monotonicClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  /// Whether a deferred call is pending.
  bool get hasPending => _timer != null;

  void request() {
    if (_disposed || _timer != null) return;
    final now = _now();
    final last = _lastFire;
    if (last == null || now - last >= interval) {
      _fire();
      return;
    }
    _timer = Timer(interval - (now - last), () {
      _timer = null;
      if (!_disposed) _fire();
    });
  }

  void _fire() {
    _lastFire = _now();
    onFire();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
