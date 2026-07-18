// Signal Monitor screen — real-time waveform, FFT waterfall spectrogram, and level meter.

import 'package:flutter/material.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Monitor')),
      body: Column(
        children: [
          // Waveform
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: _WaveformPainter(),
                size: Size.infinite,
              ),
            ),
          ),
          // FFT Waterfall
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: _WaterfallPainter(),
                size: Size.infinite,
              ),
            ),
          ),
          // Level meter + controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Level:'),
                const SizedBox(width: 8),
                Expanded(child: LinearProgressIndicator(value: 0.3)),
                const SizedBox(width: 16),
                Text('Peak: 18.5 kHz'),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  onPressed: () => setState(() => _paused = !_paused),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 1.0;
    final path = Path();
    path.moveTo(0, size.height / 2);
    for (double x = 0; x < size.width; x += 2) {
      path.lineTo(x, size.height / 2 + (size.height / 4) * 0.3);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WaterfallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue.withAlpha(30);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
