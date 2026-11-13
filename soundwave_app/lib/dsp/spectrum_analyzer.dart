// Streaming short-time spectrum analysis shared by the spectrum analyzer and
// waterfall widgets (#71, #91): Hann-windowed FFT frames with a fixed hop,
// scaled to dBFS, plus a peak-hold tracker.

import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Turns a stream of audio samples into dBFS magnitude spectra.
///
/// Scaling: a full-scale sine (amplitude 1.0) centred on a bin reads 0 dBFS
/// at that bin, i.e. bins hold the estimated sinusoid amplitude in dB.
class SpectrumAnalyzer {
  /// FFT length in samples (power of two).
  final int fftSize;

  /// Samples between the starts of consecutive frames.
  final int hopSize;

  /// Audio sample rate in Hz.
  final double sampleRate;

  /// Most frames produced for one [addSamples] call. When a large chunk
  /// would produce more (slow device, backlog), only the newest frames are
  /// computed so the display stays current instead of falling behind.
  final int maxFramesPerPush;

  final Fft _fft;
  final Float64List _window;
  final Float64List _re;
  final Float64List _im;
  final Float64List _ring;
  final double _ampScale;
  int _write = 0;
  int _filled = 0;
  int _sinceFrame = 0;

  SpectrumAnalyzer({
    this.fftSize = 1024,
    int? hopSize,
    this.sampleRate = 44100,
    this.maxFramesPerPush = 8,
  })  : hopSize = hopSize ?? fftSize ~/ 2,
        _fft = Fft(fftSize),
        _window = hannWindow(fftSize),
        _re = Float64List(fftSize),
        _im = Float64List(fftSize),
        _ring = Float64List(fftSize),
        _ampScale = 2.0 / (fftSize * 0.5) {
    if (this.hopSize <= 0) {
      throw ArgumentError.value(hopSize, 'hopSize', 'must be positive');
    }
    if (!(sampleRate > 0)) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
  }

  /// Bins from DC to Nyquist inclusive.
  int get binCount => fftSize ~/ 2 + 1;

  /// Frequency spacing between bins in Hz.
  double get binWidthHz => sampleRate / fftSize;

  /// Seconds of audio between consecutive frames.
  double get secondsPerFrame => hopSize / sampleRate;

  /// Centre frequency of bin [k] in Hz.
  double frequencyOfBin(int k) => k * binWidthHz;

  /// Nearest bin to [hz], clamped to [0, binCount - 1].
  int binForFrequency(double hz) {
    final k = (hz / binWidthHz).round();
    return k.clamp(0, binCount - 1);
  }

  /// Discards buffered samples (e.g. after a sample-rate change or pause).
  void reset() {
    _write = 0;
    _filled = 0;
    _sinceFrame = 0;
  }

  /// dBFS spectrum of exactly [fftSize] samples (oldest first).
  Float64List analyze(List<double> frame) {
    if (frame.length != fftSize) {
      throw ArgumentError('frame must have $fftSize samples');
    }
    for (var i = 0; i < fftSize; i++) {
      _re[i] = frame[i] * _window[i];
      _im[i] = 0.0;
    }
    return _spectrumFromWorkBuffers();
  }

  /// Appends [samples]; returns the spectra of frames completed by them,
  /// oldest first (at most [maxFramesPerPush], see there).
  List<Float64List> addSamples(List<double> samples) {
    // Count completed frames first so only the newest ones are computed.
    var due = 0;
    var filled = _filled;
    var since = _sinceFrame;
    for (var i = 0; i < samples.length; i++) {
      if (filled < fftSize) filled++;
      since++;
      if (filled == fftSize && since >= hopSize) {
        since = 0;
        due++;
      }
    }
    var skip = math.max(0, due - maxFramesPerPush);

    final out = <Float64List>[];
    for (var i = 0; i < samples.length; i++) {
      _ring[_write] = samples[i];
      _write = (_write + 1) % fftSize;
      if (_filled < fftSize) _filled++;
      _sinceFrame++;
      if (_filled == fftSize && _sinceFrame >= hopSize) {
        _sinceFrame = 0;
        if (skip > 0) {
          skip--;
        } else {
          out.add(_analyzeRing());
        }
      }
    }
    return out;
  }

  Float64List _analyzeRing() {
    // _write points at the oldest sample once the ring is full.
    for (var i = 0; i < fftSize; i++) {
      _re[i] = _ring[(_write + i) % fftSize] * _window[i];
      _im[i] = 0.0;
    }
    return _spectrumFromWorkBuffers();
  }

  Float64List _spectrumFromWorkBuffers() {
    _fft.transform(_re, _im);
    final n = binCount;
    final out = Float64List(n);
    for (var k = 0; k < n; k++) {
      final mag = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
      // DC and Nyquist have no mirrored negative-frequency half.
      final edge = k == 0 || k == n - 1;
      out[k] = amplitudeToDb(mag * (edge ? _ampScale / 2 : _ampScale));
    }
    return out;
  }
}

/// Per-bin peak hold: a peak is held for [holdSeconds], then falls at
/// [decayDbPerSecond] until the live spectrum catches up with it.
class PeakHold {
  final double holdSeconds;
  final double decayDbPerSecond;
  Float64List? _peaks;
  Float64List? _age;

  PeakHold({this.holdSeconds = 1.0, this.decayDbPerSecond = 20.0});

  /// Current peak spectrum, or null before the first update.
  Float64List? get peaks => _peaks;

  void reset() {
    _peaks = null;
    _age = null;
  }

  /// Folds in a new spectrum observed [dtSeconds] after the previous one.
  void update(Float64List spectrum, double dtSeconds) {
    final peaks = _peaks;
    final age = _age;
    if (peaks == null || age == null || peaks.length != spectrum.length) {
      _peaks = Float64List.fromList(spectrum);
      _age = Float64List(spectrum.length);
      return;
    }
    final dt = dtSeconds.isFinite && dtSeconds > 0 ? dtSeconds : 0.0;
    for (var k = 0; k < spectrum.length; k++) {
      final v = spectrum[k];
      if (v >= peaks[k]) {
        peaks[k] = v;
        age[k] = 0;
        continue;
      }
      age[k] += dt;
      if (age[k] > holdSeconds) {
        final decayed = peaks[k] - decayDbPerSecond * dt;
        peaks[k] = decayed > v ? decayed : v;
      }
    }
  }
}
