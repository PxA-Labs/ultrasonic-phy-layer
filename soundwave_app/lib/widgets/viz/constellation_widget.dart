// OFDM constellation diagram (#71): equalized data-subcarrier points from
// the native demodulator (sw_ofdm_equalized_symbols) over the ideal
// reference grid, with a decision-directed EVM readout.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../dsp/constellation.dart';
import 'plot_text.dart';

/// Keeps the points of the most recent frames, up to [maxPoints].
class ConstellationController extends ChangeNotifier {
  final int maxPoints;
  final List<ConstellationFrame> _frames = [];
  int _points = 0;

  ConstellationController({this.maxPoints = 4096});

  /// Frames currently shown, oldest first.
  List<ConstellationFrame> get frames => List.unmodifiable(_frames);

  ConstellationFrame? get latest => _frames.isEmpty ? null : _frames.last;

  int get pointCount => _points;

  /// Reference scheme of the newest frame (QPSK before any frame).
  ConstellationScheme get scheme => latest?.scheme ?? ConstellationScheme.qpsk;

  /// EVM of the newest frame.
  EvmResult? get evm => latest?.evm;

  void addFrame(ConstellationFrame frame) {
    if (frame.pointCount == 0) return;
    // A scheme change makes older points meaningless against the new grid.
    if (_frames.isNotEmpty && _frames.last.scheme != frame.scheme) {
      _frames.clear();
      _points = 0;
    }
    _frames.add(frame);
    _points += frame.pointCount;
    while (_frames.length > 1 && _points > maxPoints) {
      _points -= _frames.removeAt(0).pointCount;
    }
    notifyListeners();
  }

  void clear() {
    _frames.clear();
    _points = 0;
    notifyListeners();
  }
}

/// Constellation plot with EVM readout.
class ConstellationDiagram extends StatelessWidget {
  final ConstellationController controller;

  /// Half-width of the plotted I/Q square.
  final double range;

  const ConstellationDiagram({
    super.key,
    required this.controller,
    this.range = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Semantics(
            label: 'Constellation diagram',
            child: RepaintBoundary(
              child: CustomPaint(
                painter: ConstellationPainter(
                  controller: controller,
                  colors: theme.colorScheme,
                  labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
                  range: range,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _readout(controller),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  static String _readout(ConstellationController c) {
    final latest = c.latest;
    if (latest == null) return '${c.scheme.label} - EVM --';
    final evm = latest.evm;
    final crc = latest.decoded ? 'CRC ok' : 'CRC failed';
    if (evm == null) return '${latest.scheme.label} - EVM -- - $crc';
    return '${latest.scheme.label} - EVM ${evm.percent.toStringAsFixed(1)}% '
        '(${evm.db.toStringAsFixed(1)} dB) - ${evm.count} pts - $crc';
  }
}

/// Paints axes, the reference grid and the received points.
class ConstellationPainter extends CustomPainter {
  final ConstellationController controller;
  final ColorScheme colors;
  final TextStyle labelStyle;
  final double range;

  ConstellationPainter({
    required this.controller,
    required this.colors,
    required this.labelStyle,
    this.range = 1.6,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) - 8;
    if (side <= 8) return;
    final plot = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final scale = side / (2 * range);
    Offset toPx(double i, double q) =>
        plot.center + Offset(i * scale, -q * scale);

    canvas.drawRect(
      plot,
      Paint()..color = colors.surfaceContainerHighest.withValues(alpha: 0.4),
    );
    final axis = Paint()
      ..color = colors.outline
      ..strokeWidth = 0.75;
    canvas.drawLine(plot.centerLeft, plot.centerRight, axis);
    canvas.drawLine(plot.topCenter, plot.bottomCenter, axis);
    final faint = Paint()
      ..color = colors.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(plot.center, scale, faint); // unit-energy circle

    final axisStyle = labelStyle.copyWith(color: colors.onSurfaceVariant);
    final iAt = plot.centerRight - const Offset(10, 14);
    paintPlotText(canvas, 'I', iAt, axisStyle);
    paintPlotText(canvas, 'Q', plot.topCenter + const Offset(4, 0), axisStyle);

    canvas.save();
    canvas.clipRect(plot);
    final frames = controller.frames;
    for (var f = 0; f < frames.length; f++) {
      final frame = frames[f];
      // Newest frame opaque, older ones fade out.
      final alpha = f == frames.length - 1 ? 0.9 : 0.35;
      final color = frame.decoded ? colors.primary : colors.error;
      final pts = Float32List(frame.iq.length);
      final c = plot.center;
      for (var k = 0; k + 1 < frame.iq.length; k += 2) {
        pts[k] = c.dx + frame.iq[k] * scale;
        pts[k + 1] = c.dy - frame.iq[k + 1] * scale;
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();

    // Ideal points on top so they stay visible inside dense clusters.
    final ref = controller.scheme.referencePoints;
    final ring = Paint()
      ..color = colors.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var k = 0; k + 1 < ref.length; k += 2) {
      canvas.drawCircle(toPx(ref[k], ref[k + 1]), 5, ring);
    }

    if (frames.isEmpty) {
      final at = plot.center + const Offset(-70, 12);
      paintPlotText(canvas, 'No OFDM frames yet', at, axisStyle);
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.colors != colors ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.range != range;
}
