// Signal Monitor screen — spectrum analyzer, waterfall spectrogram, OFDM
// constellation and waveform (#71, #91).
//
// One SpectrumAnalyzer (Hann-windowed FFT) feeds both the spectrum and the
// waterfall; the constellation comes from the receiver's equalizer output.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsp/constellation.dart';
import '../dsp/spectrum_analyzer.dart';
import '../state/app_state.dart';
import '../widgets/viz/constellation_widget.dart';
import '../widgets/viz/spectrum_analyzer_widget.dart';
import '../widgets/viz/waterfall_widget.dart';
import '../widgets/viz/waveform_widget.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  /// FFT length shared by the spectrum and waterfall.
  static const int fftSize = 1024;

  /// Every n-th spectrum frame becomes a waterfall row (43 rows/s at
  /// 44.1 kHz with a 512-sample hop).
  static const int waterfallDecimation = 2;

  /// Rows of waterfall history (~6 s at 44.1 kHz).
  static const int waterfallRows = 256;

  /// Width at which all four plots are shown at once instead of tabs.
  static const double wideLayoutWidth = 1000;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  late AppState _state;
  StreamSubscription<Float64List>? _audioSubscription;
  StreamSubscription<ConstellationFrame>? _constellationSubscription;

  late SpectrumAnalyzer _analyzer;
  late SpectrumController _spectrum;
  late WaterfallController _waterfall;
  final WaveformController _waveform = WaveformController();
  final ConstellationController _constellation = ConstellationController();
  int _sampleRate = 0;
  int _frameCount = 0;
  bool _paused = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = Provider.of<AppState>(context, listen: false);
    if (!_initialized) {
      _initialized = true;
      _configure(_state.sampleRate);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_state.isAudioCapturing) {
        _state.startAudioCapture();
      }
      _audioSubscription = _state.audioStream.listen(_onAudio);
      _constellationSubscription =
          _state.constellationStream.listen(_constellation.addFrame);
    });
  }

  /// (Re)creates the analysis chain for [sampleRate].
  void _configure(int sampleRate) {
    final rate = sampleRate > 0 ? sampleRate : 44100;
    if (_sampleRate != 0) {
      _spectrum.dispose();
      _waterfall.dispose();
    }
    _sampleRate = rate;
    _frameCount = 0;
    _analyzer = SpectrumAnalyzer(
      fftSize: MonitorScreen.fftSize,
      sampleRate: rate.toDouble(),
    );
    _spectrum = SpectrumController(binWidthHz: _analyzer.binWidthHz);
    _waterfall = WaterfallController(
      rows: MonitorScreen.waterfallRows,
      binCount: _analyzer.binCount,
      binWidthHz: _analyzer.binWidthHz,
      secondsPerRow:
          _analyzer.secondsPerFrame * MonitorScreen.waterfallDecimation,
    );
  }

  void _onAudio(Float64List chunk) {
    if (_paused || !mounted) return;
    if (_state.sampleRate != _sampleRate && _state.sampleRate > 0) {
      setState(() => _configure(_state.sampleRate));
    }
    _waveform.addSamples(chunk);
    final dt = _analyzer.secondsPerFrame;
    for (final frame in _analyzer.addSamples(chunk)) {
      _spectrum.update(frame, dt);
      if (_frameCount++ % MonitorScreen.waterfallDecimation == 0) {
        _waterfall.addRow(frame);
      }
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) _analyzer.reset();
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _constellationSubscription?.cancel();
    _spectrum.dispose();
    _waterfall.dispose();
    _waveform.dispose();
    _constellation.dispose();
    if (!_state.isListening && _state.isAudioCapturing) {
      _state.stopAudioCapture();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final carrierHz = context.select<AppState, double>((s) => s.carrierFreq);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Signal Monitor'),
        actions: [
          IconButton(
            key: const ValueKey('monitor-pause'),
            tooltip: _paused ? 'Resume monitor' : 'Pause monitor',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            onPressed: _togglePause,
          ),
        ],
      ),
      body: Column(
        children: [
          _LevelBar(waveform: _waveform, spectrum: _spectrum),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= MonitorScreen.wideLayoutWidth;
                return wide ? _grid(carrierHz) : _tabs(carrierHz);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _spectrumPanel() => _Panel(
        title: 'Spectrum (dBFS)',
        child: SpectrumAnalyzerWidget(controller: _spectrum),
      );

  Widget _waterfallPanel(double carrierHz) => _Panel(
        title: 'Waterfall Spectrogram',
        child: WaterfallView(controller: _waterfall, carrierHz: carrierHz),
      );

  Widget _constellationPanel() => _Panel(
        title: 'OFDM Constellation (equalized)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ConstellationHint(),
            Expanded(child: ConstellationDiagram(controller: _constellation)),
          ],
        ),
      );

  Widget _waveformPanel() => _Panel(
        title: 'Waveform (Time Domain)',
        child: WaveformWidget(controller: _waveform),
      );

  Widget _grid(double carrierHz) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _spectrumPanel()),
              Expanded(child: _waterfallPanel(carrierHz)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _constellationPanel()),
              Expanded(child: _waveformPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs(double carrierHz) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Spectrum'),
              Tab(text: 'Waterfall'),
              Tab(text: 'Constellation'),
              Tab(text: 'Waveform'),
            ],
          ),
          Expanded(
            child: TabBarView(
              // Horizontal drags belong to the plots (waterfall readout).
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _spectrumPanel(),
                _waterfallPanel(carrierHz),
                _constellationPanel(),
                _waveformPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final titleStyle = theme.textTheme.bodySmall?.copyWith(color: muted);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 4),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Input level meter and the strongest ultrasonic tone.
class _LevelBar extends StatelessWidget {
  final WaveformController waveform;
  final SpectrumController spectrum;

  const _LevelBar({required this.waveform, required this.spectrum});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([waveform, spectrum]),
          builder: (context, _) {
            final db = waveform.levelDbfs.clamp(-60.0, 0.0);
            final progress = (db + 60) / 60;
            final Color meter;
            if (progress > 0.9) {
              meter = colors.error;
            } else if (progress > 0.7) {
              meter = colors.tertiary;
            } else {
              meter = colors.primary;
            }
            final peak = spectrum.peakBin(18000, 22000);
            final s = spectrum.spectrum;
            var peakText = '-- kHz';
            if (peak != null && s != null && s[peak] > -80) {
              final khz = peak * spectrum.binWidthHz / 1000;
              peakText = '${khz.toStringAsFixed(2)} kHz';
            }
            // Flexible labels wrap at large text scales instead of
            // overflowing the row.
            return Row(
              children: [
                Flexible(child: Text('Level ${db.toStringAsFixed(0)} dBFS')),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: LinearProgressIndicator(
                    semanticsLabel: 'Input level',
                    value: progress,
                    backgroundColor: colors.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(meter),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    'Peak: $peakText',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Explains what the constellation needs (OFDM mode, receiver running).
class _ConstellationHint extends StatelessWidget {
  const _ConstellationHint();

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, int>((s) => s.mode);
    final listening = context.select<AppState, bool>((s) => s.isListening);
    final style = Theme.of(context).textTheme.bodySmall;
    if (mode != 1) {
      return Text(
        'Constellation is shown for OFDM mode (select it in Settings).',
        style: style,
      );
    }
    if (listening) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Text('Start the receiver to see frames.', style: style),
        ),
        TextButton(
          onPressed: () => context.read<AppState>().toggleListening(),
          child: const Text('Start receiver'),
        ),
      ],
    );
  }
}
