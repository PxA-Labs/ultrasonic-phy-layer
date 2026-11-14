// Scrolling waterfall spectrogram (#91): time runs downwards (newest row at
// the bottom), frequency horizontally, colour = dBFS level.
//
// Rows are kept in a WaterfallBuffer and colour-mapped incrementally into an
// RGBA pixel ring; at most ~30 times a second the ring is uploaded as one
// ui.Image, which the painter draws with a single drawImageRect. Changing
// the dB range or colour map re-colours the stored dB rows.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../dsp/band_activity.dart';
import '../../dsp/waterfall_buffer.dart';
import 'colormap.dart';
import 'band_activity_semantics.dart';
import 'frame_throttle.dart';
import 'plot_text.dart';

/// Frequency ranges offered by [WaterfallView].
enum WaterfallRange {
  ultrasonic('18-22 kHz'),
  carrier('Carrier +/-500 Hz'),
  full('Full band');

  final String label;
  const WaterfallRange(this.label);

  /// (low, high) in Hz for this range, clamped to [0, nyquistHz].
  (double, double) bounds(double carrierHz, double nyquistHz) {
    final (double lo, double hi) = switch (this) {
      WaterfallRange.ultrasonic => (18000.0, 22000.0),
      WaterfallRange.carrier => (carrierHz - 500, carrierHz + 500),
      WaterfallRange.full => (0.0, nyquistHz),
    };
    final low = clampTo(lo, 0, nyquistHz - 1);
    return (low, clampTo(hi, low + 1, nyquistHz));
  }
}

/// Owns the waterfall history, colour mapping and the rendered image.
class WaterfallController extends ChangeNotifier {
  final WaterfallBuffer buffer;

  /// Frequency spacing between bins in Hz.
  final double binWidthHz;

  /// Seconds of audio between consecutive rows.
  final double secondsPerRow;

  /// Limits of the dB range control.
  static const double rangeFloorDb = -140;
  static const double rangeCeilDb = 0;

  final Uint8List _pixels;
  late final FrameThrottle _throttle;
  ui.Image? _image;
  bool _paused = false;
  double _minDb;
  double _maxDb;
  WaterfallColormap _colormap;
  bool _decoding = false;
  bool _dirty = false;
  bool _disposed = false;

  WaterfallController({
    int rows = 200,
    required int binCount,
    required this.binWidthHz,
    required this.secondsPerRow,
    double minDb = -110,
    double maxDb = -30,
    WaterfallColormap colormap = WaterfallColormap.viridis,
    Duration frameInterval = const Duration(milliseconds: 33),
  })  : buffer = WaterfallBuffer(capacity: rows, binCount: binCount),
        _pixels = Uint8List(rows * binCount * 4),
        _minDb = minDb,
        _maxDb = maxDb,
        _colormap = colormap {
    if (!(maxDb > minDb)) {
      throw ArgumentError('maxDb must be greater than minDb');
    }
    _throttle = FrameThrottle(interval: frameInterval, onFire: _renderImage);
  }

  int get rows => buffer.capacity;
  int get binCount => buffer.binCount;
  double get nyquistHz => (binCount - 1) * binWidthHz;
  bool get paused => _paused;
  double get minDb => _minDb;
  double get maxDb => _maxDb;
  WaterfallColormap get colormap => _colormap;

  /// Latest rendered image (rows x bins, oldest row on top), if any.
  ui.Image? get image => _image;

  /// Appends one spectrum row (dBFS per bin). Ignored while paused.
  void addRow(List<double> spectrumDb) {
    if (_paused || _disposed) return;
    buffer.push(spectrumDb);
    _colorSlot(buffer.slotOfAge(0), spectrumDb);
    _markDirty();
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    notifyListeners();
  }

  void togglePause() => setPaused(!_paused);

  void setDbRange(double minDb, double maxDb) {
    if (!(maxDb > minDb)) return;
    if (minDb == _minDb && maxDb == _maxDb) return;
    _minDb = minDb;
    _maxDb = maxDb;
    _recolorAll();
    notifyListeners();
  }

  void setColormap(WaterfallColormap value) {
    if (value == _colormap) return;
    _colormap = value;
    _recolorAll();
    notifyListeners();
  }

  void clear() {
    buffer.clear();
    _pixels.fillRange(0, _pixels.length, 0);
    _markDirty();
  }

  /// Level in dBFS at [hz] in the row of [age] (0 = newest), or null.
  double? valueAt(double hz, int age) {
    final bin = (hz / binWidthHz).round();
    if (bin < 0 || bin >= binCount) return null;
    if (age < 0 || age >= buffer.length) return null;
    return buffer.valueAt(age, bin);
  }

  /// RGBA pixels in display order: image row 0 is the oldest slot, the last
  /// row the newest; rows not yet filled are transparent.
  @visibleForTesting
  Uint8List buildPixels() {
    final rowBytes = binCount * 4;
    final out = Uint8List(rows * rowBytes);
    final filled = buffer.length;
    for (var r = 0; r < rows; r++) {
      final age = rows - 1 - r;
      if (age >= filled) continue;
      final src = buffer.slotOfAge(age) * rowBytes;
      out.setRange(r * rowBytes, (r + 1) * rowBytes, _pixels, src);
    }
    return out;
  }

  void _colorSlot(int slot, List<double> row) {
    final lut = _colormap.rgbaLut;
    final scale = 1 / (_maxDb - _minDb);
    var o = slot * binCount * 4;
    for (var k = 0; k < binCount; k++) {
      final li = WaterfallColormap.indexOf((row[k] - _minDb) * scale) * 4;
      _pixels[o++] = lut[li];
      _pixels[o++] = lut[li + 1];
      _pixels[o++] = lut[li + 2];
      _pixels[o++] = lut[li + 3];
    }
  }

  void _recolorAll() {
    for (var age = 0; age < buffer.length; age++) {
      _colorSlot(buffer.slotOfAge(age), buffer.rowAt(age));
    }
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _throttle.request();
  }

  void _renderImage() {
    if (_disposed || _decoding || !_dirty) return;
    _dirty = false;
    _decoding = true;
    ui.decodeImageFromPixels(
      buildPixels(),
      binCount,
      rows,
      ui.PixelFormat.rgba8888,
      (img) {
        _decoding = false;
        if (_disposed) {
          img.dispose();
          return;
        }
        _image?.dispose();
        _image = img;
        notifyListeners();
        if (_dirty) _throttle.request();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _throttle.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// The waterfall plot with axes and a hover/touch readout.
class WaterfallPlot extends StatefulWidget {
  final WaterfallController controller;
  final double minFrequencyHz;
  final double maxFrequencyHz;

  /// Band summary exposed as the plot's semantics value (#93).
  final ValueListenable<BandActivity>? activity;

  const WaterfallPlot({
    super.key,
    required this.controller,
    required this.minFrequencyHz,
    required this.maxFrequencyHz,
    this.activity,
  });

  @override
  State<WaterfallPlot> createState() => _WaterfallPlotState();
}

class _WaterfallPlotState extends State<WaterfallPlot> {
  Offset? _pointer;

  void _setPointer(Offset? p) {
    if (p != _pointer) setState(() => _pointer = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BandActivitySemantics(
      activity: widget.activity,
      label: 'Waterfall spectrogram: frequency content over time',
      child: MouseRegion(
        onHover: (e) => _setPointer(e.localPosition),
        onExit: (_) => _setPointer(null),
        child: GestureDetector(
          onPanDown: (d) => _setPointer(d.localPosition),
          onPanUpdate: (d) => _setPointer(d.localPosition),
          onPanEnd: (_) => _setPointer(null),
          onPanCancel: () => _setPointer(null),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: WaterfallPainter(
                controller: widget.controller,
                colors: theme.colorScheme,
                labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
                minFrequencyHz: widget.minFrequencyHz,
                maxFrequencyHz: widget.maxFrequencyHz,
                pointer: _pointer,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the waterfall image, frequency/time axes and the readout.
class WaterfallPainter extends CustomPainter {
  final WaterfallController controller;
  final ColorScheme colors;
  final TextStyle labelStyle;
  final double minFrequencyHz;
  final double maxFrequencyHz;
  final Offset? pointer;

  static const double leftAxis = 44;
  static const double bottomAxis = 18;

  WaterfallPainter({
    required this.controller,
    required this.colors,
    required this.labelStyle,
    required this.minFrequencyHz,
    required this.maxFrequencyHz,
    this.pointer,
  }) : super(repaint: controller);

  /// Plot area within a canvas of [size].
  static Rect plotRect(Size size) =>
      Rect.fromLTRB(leftAxis, 4, size.width - 4, size.height - bottomAxis);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    if (plot.width <= 4 || plot.height <= 4) return;
    final fMin = minFrequencyHz;
    final fMax = maxFrequencyHz > fMin ? maxFrequencyHz : fMin + 1;
    final rows = controller.rows;
    final binWidth = controller.binWidthHz;

    canvas.drawRect(plot, Paint()..color = colors.surfaceContainerHighest);
    final image = controller.image;
    if (image != null) {
      final src = Rect.fromLTRB(
        fMin / binWidth + 0.5,
        0,
        fMax / binWidth + 0.5,
        image.height.toDouble(),
      );
      canvas.drawImageRect(
        image,
        src,
        plot,
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      );
    }

    final axisStyle = labelStyle.copyWith(color: colors.onSurfaceVariant);
    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    final step = frequencyTickStep(fMax - fMin);
    for (var f = (fMin / step).ceil() * step; f <= fMax; f += step) {
      final x = plot.left + (f - fMin) / (fMax - fMin) * plot.width;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final at = Offset(x - 8, plot.bottom + 2);
      paintPlotText(canvas, formatKhz(f), at, axisStyle);
    }
    final span = rows * controller.secondsPerRow;
    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = plot.bottom - frac * plot.height;
      final secs = frac * span;
      final text = frac == 0 ? 'now' : '-${secs.toStringAsFixed(1)}s';
      final at = Offset(2, clampTo(y - 6, 0, size.height - 12));
      paintPlotText(canvas, text, at, axisStyle);
    }

    if (controller.paused) {
      final at = Offset(plot.right - 52, plot.top + 2);
      paintPlotText(canvas, 'PAUSED', at, axisStyle);
    }

    final p = pointer;
    if (p != null && plot.contains(p)) {
      final hz = fMin + (p.dx - plot.left) / plot.width * (fMax - fMin);
      final row = ((p.dy - plot.top) / plot.height * rows).floor();
      final age = rows - 1 - row;
      final db = controller.valueAt(hz, age);
      final cross = Paint()
        ..color = colors.onSurface.withValues(alpha: 0.7)
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(p.dx, plot.top), Offset(p.dx, plot.bottom), cross);
      canvas.drawLine(Offset(plot.left, p.dy), Offset(plot.right, p.dy), cross);
      final secs = (age * controller.secondsPerRow).toStringAsFixed(2);
      final level = db == null ? '--' : db.toStringAsFixed(1);
      final text = '${(hz / 1000).toStringAsFixed(3)} kHz  $level dB  '
          '-${secs}s';
      final box = Rect.fromLTWH(plot.left + 4, plot.top + 4, 180, 16);
      canvas.drawRect(
        box,
        Paint()..color = colors.surface.withValues(alpha: 0.85),
      );
      final style = labelStyle.copyWith(color: colors.onSurface);
      paintPlotText(canvas, text, box.topLeft + const Offset(4, 1), style);
    }
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.colors != colors ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.minFrequencyHz != minFrequencyHz ||
      oldDelegate.maxFrequencyHz != maxFrequencyHz ||
      oldDelegate.pointer != pointer;
}

/// Waterfall plot plus its controls: pause, colour map, frequency range and
/// dB range (gain/contrast).
class WaterfallView extends StatefulWidget {
  final WaterfallController controller;

  /// Centre of the "Carrier +/-500 Hz" zoom.
  final double carrierHz;

  /// Band summary for screen readers (#93).
  final ValueListenable<BandActivity>? activity;

  const WaterfallView({
    super.key,
    required this.controller,
    this.carrierHz = 19000,
    this.activity,
  });

  @override
  State<WaterfallView> createState() => _WaterfallViewState();
}

class _WaterfallViewState extends State<WaterfallView> {
  WaterfallRange _range = WaterfallRange.ultrasonic;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final (lo, hi) = _range.bounds(widget.carrierHz, c.nyquistHz);
    return Column(
      children: [
        Expanded(
          child: WaterfallPlot(
            controller: c,
            minFrequencyHz: lo,
            maxFrequencyHz: hi,
            activity: widget.activity,
          ),
        ),
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => _controls(context, c),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context, WaterfallController c) {
    final small = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        IconButton(
          key: const ValueKey('waterfall-pause'),
          tooltip: c.paused ? 'Resume waterfall' : 'Pause waterfall',
          icon: Icon(c.paused ? Icons.play_arrow : Icons.pause),
          onPressed: c.togglePause,
        ),
        DropdownButton<WaterfallColormap>(
          key: const ValueKey('waterfall-colormap'),
          value: c.colormap,
          onChanged: (v) {
            if (v != null) c.setColormap(v);
          },
          items: [
            for (final m in WaterfallColormap.values)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
        ),
        DropdownButton<WaterfallRange>(
          key: const ValueKey('waterfall-range'),
          value: _range,
          onChanged: (v) {
            if (v != null) setState(() => _range = v);
          },
          items: [
            for (final r in WaterfallRange.values)
              DropdownMenuItem(value: r, child: Text(r.label)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${c.minDb.toStringAsFixed(0)} to '
              '${c.maxDb.toStringAsFixed(0)} dB',
              style: small,
            ),
            SizedBox(
              width: 200,
              child: RangeSlider(
                semanticFormatterCallback: (v) => '${v.round()} dB',
                key: const ValueKey('waterfall-db-range'),
                min: WaterfallController.rangeFloorDb,
                max: WaterfallController.rangeCeilDb,
                divisions: 28,
                values: RangeValues(c.minDb, c.maxDb),
                onChanged: (v) => c.setDbRange(v.start, v.end),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
