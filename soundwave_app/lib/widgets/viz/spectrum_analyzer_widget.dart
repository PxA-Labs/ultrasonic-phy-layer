// Real-time spectrum analyzer: dBFS magnitude spectrum with the ultrasonic
// band highlighted and a peak-hold trace (#71).

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../dsp/band_activity.dart';
import '../../dsp/fft.dart';
import '../../dsp/spectrum_analyzer.dart';
import 'band_activity_semantics.dart';
import 'frame_throttle.dart';
import 'plot_text.dart';

/// Latest spectrum plus peak hold; repaints are throttled to [frameInterval].
class SpectrumController extends ChangeNotifier {
  /// Frequency spacing between bins in Hz.
  double binWidthHz;

  /// Plot range in dBFS.
  final double minDb;
  final double maxDb;

  final PeakHold peakHold;
  late final FrameThrottle _throttle;
  Float64List? _spectrum;

  SpectrumController({
    required this.binWidthHz,
    this.minDb = -120.0,
    this.maxDb = 0.0,
    PeakHold? peakHold,
    Duration frameInterval = const Duration(milliseconds: 33),
  }) : peakHold = peakHold ?? PeakHold() {
    _throttle = FrameThrottle(interval: frameInterval, onFire: notifyListeners);
  }

  /// Most recent spectrum (dBFS per bin), or null before the first frame.
  Float64List? get spectrum => _spectrum;

  /// Peak-hold spectrum, or null before the first frame.
  Float64List? get peaks => peakHold.peaks;

  /// Adds a spectrum computed [dtSeconds] after the previous one.
  void update(Float64List spectrum, double dtSeconds) {
    _spectrum = spectrum;
    peakHold.update(spectrum, dtSeconds);
    _throttle.request();
  }

  /// Index of the strongest bin within [lowHz, highHz], or null.
  int? peakBin(double lowHz, double highHz) {
    final s = _spectrum;
    if (s == null || s.isEmpty || binWidthHz <= 0) return null;
    final lo = (lowHz / binWidthHz).ceil().clamp(0, s.length - 1);
    final hi = (highHz / binWidthHz).floor().clamp(0, s.length - 1);
    int? best;
    for (var k = lo; k <= hi; k++) {
      if (best == null || s[k] > s[best]) best = k;
    }
    return best;
  }

  void clear() {
    _spectrum = null;
    peakHold.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _throttle.dispose();
    super.dispose();
  }
}

/// Spectrum analyzer plot driven by a [SpectrumController].
class SpectrumAnalyzerWidget extends StatelessWidget {
  final SpectrumController controller;

  /// Highlighted band (default: the 18-22 kHz ultrasonic band).
  final double bandLowHz;
  final double bandHighHz;

  /// Displayed frequency range; [maxFrequencyHz] null means Nyquist.
  final double minFrequencyHz;
  final double? maxFrequencyHz;

  /// Band summary exposed as the plot's semantics value (#93).
  final ValueListenable<BandActivity>? activity;

  const SpectrumAnalyzerWidget({
    super.key,
    required this.controller,
    this.activity,
    this.bandLowHz = 18000,
    this.bandHighHz = 22000,
    this.minFrequencyHz = 0,
    this.maxFrequencyHz,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BandActivitySemantics(
      activity: activity,
      label: 'Spectrum analyzer: signal level by frequency',
      child: RepaintBoundary(
        child: CustomPaint(
          painter: SpectrumPainter(
            controller: controller,
            colors: theme.colorScheme,
            labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
            bandLowHz: bandLowHz,
            bandHighHz: bandHighHz,
            minFrequencyHz: minFrequencyHz,
            maxFrequencyHz: maxFrequencyHz,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Paints the spectrum, peak hold, band highlight and axes.
class SpectrumPainter extends CustomPainter {
  final SpectrumController controller;
  final ColorScheme colors;
  final TextStyle labelStyle;
  final double bandLowHz;
  final double bandHighHz;
  final double minFrequencyHz;
  final double? maxFrequencyHz;

  static const double leftAxis = 40;
  static const double bottomAxis = 18;

  SpectrumPainter({
    required this.controller,
    required this.colors,
    required this.labelStyle,
    required this.bandLowHz,
    required this.bandHighHz,
    required this.minFrequencyHz,
    required this.maxFrequencyHz,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      leftAxis,
      4,
      size.width - 4,
      size.height - bottomAxis,
    );
    if (plot.width <= 4 || plot.height <= 4) return;

    final spectrum = controller.spectrum;
    final binCount = spectrum?.length ?? 0;
    final binWidth = controller.binWidthHz;
    final nyquist = binCount > 1 ? (binCount - 1) * binWidth : 22050.0;
    final fMin = minFrequencyHz.clamp(0.0, nyquist - 1);
    final fMax = (maxFrequencyHz ?? nyquist).clamp(fMin + 1, nyquist);
    final minDb = controller.minDb;
    final maxDb = controller.maxDb;

    double xOf(double hz) {
      return plot.left + (hz - fMin) / (fMax - fMin) * plot.width;
    }

    double yOf(double db) {
      final t = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
      return plot.bottom - t * plot.height;
    }

    final background = colors.surfaceContainerHighest.withValues(alpha: 0.4);
    canvas.drawRect(plot, Paint()..color = background);

    // Ultrasonic band highlight.
    final bandL = xOf(bandLowHz.clamp(fMin, fMax));
    final bandR = xOf(bandHighHz.clamp(fMin, fMax));
    if (bandR > bandL) {
      final band = Rect.fromLTRB(bandL, plot.top, bandR, plot.bottom);
      final bandColor = colors.primary.withValues(alpha: 0.14);
      canvas.drawRect(band, Paint()..color = bandColor);
      paintPlotText(
        canvas,
        '${formatKhz(bandLowHz)}-${formatKhz(bandHighHz)} kHz',
        Offset(bandL + 2, plot.top + 2),
        labelStyle.copyWith(color: colors.primary),
      );
    }

    // Grid and axis labels.
    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    final axisStyle = labelStyle.copyWith(color: colors.onSurfaceVariant);
    for (var db = (maxDb / 20).floor() * 20.0; db >= minDb; db -= 20) {
      final y = yOf(db);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      paintPlotText(canvas, db.toStringAsFixed(0), Offset(2, y - 6), axisStyle);
    }
    final step = frequencyTickStep(fMax - fMin);
    for (var f = (fMin / step).ceil() * step; f <= fMax; f += step) {
      final x = xOf(f);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final at = Offset(x - 8, plot.bottom + 2);
      paintPlotText(canvas, formatKhz(f), at, axisStyle);
    }

    if (spectrum == null || binCount < 2) {
      final at = plot.center - const Offset(50, 6);
      paintPlotText(canvas, 'Waiting for audio...', at, axisStyle);
      return;
    }

    canvas.save();
    canvas.clipRect(plot);
    final line = _tracePath(spectrum, binWidth, xOf, yOf);
    final fill = Path.from(line)
      ..lineTo(xOf(fMax), plot.bottom)
      ..lineTo(xOf(fMin), plot.bottom)
      ..close();
    final fillColor = colors.primary.withValues(alpha: 0.18);
    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final peaks = controller.peaks;
    if (peaks != null && peaks.length == binCount) {
      canvas.drawPath(
        _tracePath(peaks, binWidth, xOf, yOf),
        Paint()
          ..color = colors.tertiary.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();

    final peak = controller.peakBin(bandLowHz, bandHighHz);
    if (peak != null && spectrum[peak] > kSpectrumFloorDb) {
      final hz = peak * binWidth;
      final p = Offset(xOf(hz), yOf(spectrum[peak]));
      if (plot.contains(p)) {
        canvas.drawCircle(p, 3, Paint()..color = colors.tertiary);
        final label = '${(hz / 1000).toStringAsFixed(2)} kHz '
            '${spectrum[peak].toStringAsFixed(0)} dB';
        final y = clampTo(p.dy - 16, plot.top, plot.bottom - 12);
        final at = Offset(clampTo(p.dx - 40, plot.left, plot.right - 80), y);
        paintPlotText(
          canvas,
          label,
          at,
          labelStyle.copyWith(color: colors.tertiary),
        );
      }
    }
  }

  static Path _tracePath(
    Float64List db,
    double binWidth,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    final path = Path();
    for (var k = 0; k < db.length; k++) {
      final x = xOf(k * binWidth);
      final y = yOf(db[k]);
      if (k == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.colors != colors ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.bandLowHz != bandLowHz ||
      oldDelegate.bandHighHz != bandHighHz ||
      oldDelegate.minFrequencyHz != minFrequencyHz ||
      oldDelegate.maxFrequencyHz != maxFrequencyHz;
}
