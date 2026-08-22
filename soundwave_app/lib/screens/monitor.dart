// Signal Monitor screen — real-time waveform, FFT waterfall spectrogram, and level meter.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

// Pure Dart Complex Number Implementation for FFT
class Complex {
  final double r;
  final double i;
  const Complex(this.r, this.i);

  Complex operator +(Complex o) => Complex(r + o.r, i + o.i);
  Complex operator -(Complex o) => Complex(r - o.r, i - o.i);
  Complex operator *(Complex o) =>
      Complex(r * o.r - i * o.i, r * o.i + i * o.r);
}

// Cooley-Tukey Radix-2 FFT
List<Complex> fft(List<Complex> x) {
  final int n = x.length;
  if (n <= 1) return x;

  final List<Complex> even = List.generate(n ~/ 2, (i) => x[2 * i]);
  final List<Complex> odd = List.generate(n ~/ 2, (i) => x[2 * i + 1]);

  final List<Complex> evenFft = fft(even);
  final List<Complex> oddFft = fft(odd);

  final List<Complex> result = List.filled(n, const Complex(0, 0));
  for (int k = 0; k < n ~/ 2; k++) {
    final double p = -2.0 * math.pi * k / n;
    final Complex t = Complex(math.cos(p), math.sin(p)) * oddFft[k];
    result[k] = evenFft[k] + t;
    result[k + n ~/ 2] = evenFft[k] - t;
  }
  return result;
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  StreamSubscription<List<double>>? _audioSubscription;
  final List<double> _waveformSamples = List.filled(256, 0.0);
  final List<double> _fftSlidingBuffer = [];
  final List<List<double>> _waterfallHistory = [];
  bool _paused = false;
  double _peakFreqHz = 0.0;
  double _dbfs = -60.0;
  late AppState _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = Provider.of<AppState>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_state.isAudioCapturing) {
        _state.startAudioCapture();
      }
      _subscribeToAudio(_state);
    });
  }

  void _subscribeToAudio(AppState state) {
    _audioSubscription = state.audioStream.listen((chunk) {
      if (_paused || !mounted) return;

      setState(() {
        // Update waveform samples (keep last 256 samples)
        if (chunk.length >= 256) {
          for (int i = 0; i < 256; i++) {
            _waveformSamples[i] = chunk[chunk.length - 256 + i];
          }
        } else {
          _waveformSamples.removeRange(0, chunk.length);
          _waveformSamples.addAll(chunk);
        }

        // Add to FFT sliding buffer
        _fftSlidingBuffer.addAll(chunk);

        // Process 512-point FFT if enough samples
        while (_fftSlidingBuffer.length >= 512) {
          final List<double> fftInput = _fftSlidingBuffer.sublist(0, 512);
          _fftSlidingBuffer.removeRange(
              0, 256); // 50% overlap for smooth waterfall

          // Calculate dBFS Level Meter
          double sumSq = 0.0;
          for (final s in fftInput) {
            sumSq += s * s;
          }
          final rms = math.sqrt(sumSq / 512);
          _dbfs = rms > 0.0 ? 20 * math.log(rms) / math.ln10 : -60.0;
          if (_dbfs < -60.0) _dbfs = -60.0;
          if (_dbfs > 0.0) _dbfs = 0.0;

          // Apply Hann Window
          final List<Complex> complexInput = List.generate(512, (i) {
            final w = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / 511));
            return Complex(fftInput[i] * w, 0.0);
          });

          // Run FFT
          final complexOutput = fft(complexInput);

          // Compute Magnitudes (keep first 256 bins)
          final List<double> magnitudes = List.generate(256, (i) {
            final double mag = math.sqrt(
              complexOutput[i].r * complexOutput[i].r +
                  complexOutput[i].i * complexOutput[i].i,
            );
            return mag;
          });

          // Find Peak Frequency in 15 kHz - 21 kHz range
          // Bin width = 44100 / 512 = 86.13 Hz
          const binWidth = 44100 / 512;
          final int startBin = (15000 / binWidth).round();
          final int endBin = (21000 / binWidth).round();
          double maxMag = -1.0;
          int peakBin = 0;

          for (int i = startBin; i <= endBin; i++) {
            if (magnitudes[i] > maxMag) {
              maxMag = magnitudes[i];
              peakBin = i;
            }
          }

          if (maxMag > 0.01) {
            _peakFreqHz = peakBin * binWidth;
          } else {
            _peakFreqHz = 0.0;
          }

          // Normalize magnitudes for heatmap display (0.0 to 1.0)
          final List<double> normalized = List.generate(256, (i) {
            final magDb = magnitudes[i] > 0.0
                ? 20 * math.log(magnitudes[i]) / math.ln10
                : -100.0;
            // Map -80dB..0dB to 0.0..1.0
            double norm = (magDb + 80.0) / 80.0;
            if (norm < 0.0) norm = 0.0;
            if (norm > 1.0) norm = 1.0;
            return norm;
          });

          // Insert into waterfall history
          _waterfallHistory.insert(0, normalized);
          if (_waterfallHistory.length > 80) {
            _waterfallHistory.removeLast();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    if (!_state.isListening && _state.isAudioCapturing) {
      _state.stopAudioCapture();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Map dbfs (-60..0) to level indicator progress (0..1)
    final double levelProgress = (_dbfs + 60.0) / 60.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Real-Time Signal Monitor')),
      body: Column(
        children: [
          // Waveform Card
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waveform (Time Domain)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    Expanded(
                      child: CustomPaint(
                        painter: _WaveformPainter(samples: _waveformSamples),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Spectrogram Card
          Expanded(
            flex: 3,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waterfall Spectrogram (FFT Heatmap)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: CustomPaint(
                          painter:
                              _WaterfallPainter(history: _waterfallHistory),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Control Bar / Level Meter
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('Level (dBFS):'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: levelProgress,
                      backgroundColor: Colors.grey.shade800,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        levelProgress > 0.9
                            ? Colors.red
                            : (levelProgress > 0.7
                                ? Colors.yellow
                                : Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _peakFreqHz > 0
                        ? 'Peak: ${(_peakFreqHz / 1000).toStringAsFixed(2)} kHz'
                        : 'Peak: -- kHz',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                    onPressed: () {
                      setState(() {
                        _paused = !_paused;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  _WaveformPainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final double midY = size.height / 2;
    final double stepX = size.width / (samples.length - 1);

    path.moveTo(0, midY);
    for (int i = 0; i < samples.length; i++) {
      final double x = i * stepX;
      // Multiply amplitude by height/2 for drawing scaling
      final double y = midY - samples[i] * midY * 0.9;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class _WaterfallPainter extends CustomPainter {
  final List<List<double>> history;
  _WaterfallPainter({required this.history});

  Color _getWaterfallColor(double val) {
    if (val < 0.25) {
      return Color.lerp(Colors.blue.shade900, Colors.cyan, val / 0.25)!;
    } else if (val < 0.5) {
      return Color.lerp(Colors.cyan, Colors.green, (val - 0.25) / 0.25)!;
    } else if (val < 0.75) {
      return Color.lerp(Colors.green, Colors.yellow, (val - 0.5) / 0.25)!;
    } else {
      return Color.lerp(Colors.yellow, Colors.red, (val - 0.75) / 0.25)!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final double rowHeight = size.height / 80; // Show up to 80 rows
    final double colWidth = size.width / 128; // Group 256 bins into 128 cols

    for (int r = 0; r < history.length; r++) {
      final rowData = history[r];
      final double y = r * rowHeight;

      for (int c = 0; c < 128; c++) {
        // Average two adjacent FFT bins for compression
        final double val = (rowData[2 * c] + rowData[2 * c + 1]) / 2;
        final double x = c * colWidth;

        final paint = Paint()..color = _getWaterfallColor(val);
        canvas.drawRect(
          Rect.fromLTWH(x, y, colWidth + 0.5, rowHeight + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter oldDelegate) => true;
}
