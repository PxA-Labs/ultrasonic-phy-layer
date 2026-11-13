// Small text and axis helpers shared by the visualizer painters.

import 'package:flutter/painting.dart';

/// Paints [text] with its top-left corner at [at].
void paintPlotText(Canvas canvas, String text, Offset at, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
  tp.dispose();
}

/// Formats [hz] in kHz with at most one decimal ("18", "19.5").
String formatKhz(double hz) {
  final k = hz / 1000;
  if (k == k.roundToDouble()) return k.toStringAsFixed(0);
  final one = k.toStringAsFixed(1);
  return double.parse(one) == k ? one : k.toStringAsFixed(2);
}

/// Tick spacing in Hz giving at most about 8 labels over [spanHz].
double frequencyTickStep(double spanHz) {
  const steps = [100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
  for (final s in steps) {
    if (spanHz / s <= 8) return s;
  }
  return 20000.0;
}

/// [v] clamped to [lo, hi]; returns [lo] when the range is empty (hi < lo),
/// where num.clamp would throw.
double clampTo(double v, double lo, double hi) {
  if (hi < lo || v < lo) return lo;
  return v > hi ? hi : v;
}
