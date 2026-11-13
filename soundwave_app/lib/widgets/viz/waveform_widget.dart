// Time-domain waveform (oscilloscope) view and input level for the monitor.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../dsp/fft.dart';
import 'frame_throttle.dart';

/// Most recent [windowSize] samples and the RMS level of the last chunk.
class WaveformController extends ChangeNotifier {
  final int windowSize;
  final Float32List _samples;
  late final FrameThrottle _throttle;
  double _levelDbfs = kSpectrumFloorDb;

  WaveformController({
    this.windowSize = 512,
    Duration frameInterval = const Duration(milliseconds: 33),
  }) : _samples = Float32List(windowSize) {
    _throttle = FrameThrottle(interval: frameInterval, onFire: notifyListeners);
  }

  /// Oldest-first view of the latest samples.
  Float32List get samples => _samples;

  /// RMS level of the most recent chunk in dBFS.
  double get levelDbfs => _levelDbfs;

  void addSamples(List<double> chunk) {
    if (chunk.isEmpty) return;
    final n = windowSize;
    if (chunk.length >= n) {
      for (var i = 0; i < n; i++) {
        _samples[i] = chunk[chunk.length - n + i];
      }
    } else {
      final keep = n - chunk.length;
      _samples.setRange(0, keep, _samples, chunk.length);
      for (var i = 0; i < chunk.length; i++) {
        _samples[keep + i] = chunk[i];
      }
    }
    _levelDbfs = rmsDbfs(chunk);
    _throttle.request();
  }

  @override
  void dispose() {
    _throttle.dispose();
    super.dispose();
  }
}

class WaveformWidget extends StatelessWidget {
  final WaveformController controller;

  const WaveformWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Waveform',
      child: RepaintBoundary(
        child: CustomPaint(
          painter: WaveformPainter(
            controller: controller,
            colors: Theme.of(context).colorScheme,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final WaveformController controller;
  final ColorScheme colors;

  WaveformPainter({required this.controller, required this.colors})
      : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final samples = controller.samples;
    if (size.width <= 0 || size.height <= 0 || samples.length < 2) return;
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = colors.outlineVariant
        ..strokeWidth = 0.5,
    );
    final stepX = size.width / (samples.length - 1);
    final path = Path()..moveTo(0, midY - samples[0] * midY * 0.9);
    for (var i = 1; i < samples.length; i++) {
      final v = samples[i].clamp(-1.0, 1.0);
      path.lineTo(i * stepX, midY - v * midY * 0.9);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.colors != colors;
}
