// Audio service abstraction — capture and playback via native C API or platform fallback.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ffi';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';

class AudioDevice {
  final String name;
  final int id;
  const AudioDevice({required this.name, required this.id});
}

abstract class AudioService {
  Future<void> startCapture();
  Future<void> stopCapture();
  Stream<Float64List> get audioStream;

  Future<void> startPlayback();
  Future<void> stopPlayback();
  Future<void> enqueueForPlayback(Float64List samples);

  bool get isCapturing;
  bool get isPlaying;
  List<AudioDevice> get inputDevices;
  List<AudioDevice> get outputDevices;

  factory AudioService.preferred(Map<String, dynamic> config) {
    try {
      return NativeAudioService(config);
    } catch (e) {
      print('NativeAudioService initialization failed ($e). Falling back to RecordAudioService.');
      return RecordAudioService();
    }
  }
}

// Preferred: Native Audio Service using C miniaudio bridge via dart:ffi
class NativeAudioService implements AudioService {
  final Map<String, dynamic> _configMap;
  late final Pointer<SwConfig> _nativeConfig;
  Pointer<Void>? _captureHandle;
  Pointer<Void>? _playbackHandle;
  Timer? _captureTimer;

  bool _isCapturing = false;
  bool _isPlaying = false;

  final StreamController<Float64List> _audioStreamController = StreamController<Float64List>.broadcast();

  NativeAudioService(this._configMap) {
    _nativeConfig = SwConfig.fromMap(_configMap);
    // Initialize native library to verify FFI library loads
    SoundwaveNative.instance;
  }

  @override
  bool get isCapturing => _isCapturing;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<Float64List> get audioStream => _audioStreamController.stream;

  @override
  List<AudioDevice> get inputDevices => [const AudioDevice(name: 'Default Microphone (Native)', id: 0)];

  @override
  List<AudioDevice> get outputDevices => [const AudioDevice(name: 'Default Speaker (Native)', id: 0)];

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    _captureHandle = SoundwaveNative.instance.audioCaptureStart(_nativeConfig);
    _isCapturing = true;

    // Poll the native capture ring buffer every 10ms
    _captureTimer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (!_isCapturing || _captureHandle == null) return;
      try {
        // Read 10ms of samples at 44100Hz (~441 float samples)
        final samples = SoundwaveNative.instance.audioCaptureRead(_captureHandle!, 441);
        if (samples.isNotEmpty) {
          final doubleSamples = Float64List(samples.length);
          for (int i = 0; i < samples.length; i++) {
            doubleSamples[i] = samples[i].toDouble();
          }
          _audioStreamController.add(doubleSamples);
        }
      } catch (e) {
        print('Native capture read error: $e');
      }
    });
  }

  @override
  Future<void> stopCapture() async {
    if (!_isCapturing) return;

    _captureTimer?.cancel();
    _captureTimer = null;

    if (_captureHandle != null) {
      SoundwaveNative.instance.audioCaptureStop(_captureHandle!);
      _captureHandle = null;
    }
    _isCapturing = false;
  }

  @override
  Future<void> startPlayback() async {
    if (_isPlaying) return;

    _playbackHandle = SoundwaveNative.instance.audioPlaybackStart(_nativeConfig);
    _isPlaying = true;
  }

  @override
  Future<void> stopPlayback() async {
    if (!_isPlaying) return;

    if (_playbackHandle != null) {
      SoundwaveNative.instance.audioPlaybackStop(_playbackHandle!);
      _playbackHandle = null;
    }
    _isPlaying = false;
  }

  @override
  Future<void> enqueueForPlayback(Float64List samples) async {
    if (!_isPlaying || _playbackHandle == null) return;

    final floatSamples = Float32List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      floatSamples[i] = samples[i].toFloat();
    }
    SoundwaveNative.instance.audioPlaybackWrite(_playbackHandle!, floatSamples);
  }

  void dispose() {
    stopCapture();
    stopPlayback();
    calloc.free(_nativeConfig);
  }
}

// Fallback: Audio Service using record and audioplayers packages
class RecordAudioService implements AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<int>>? _recordSubscription;
  bool _isCapturing = false;
  bool _isPlaying = false;

  final List<double> _playbackQueue = [];

  final StreamController<Float64List> _audioStreamController = StreamController<Float64List>.broadcast();

  @override
  bool get isCapturing => _isCapturing;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Stream<Float64List> get audioStream => _audioStreamController.stream;

  @override
  List<AudioDevice> get inputDevices => [const AudioDevice(name: 'Default Microphone (Fallback)', id: 0)];

  @override
  List<AudioDevice> get outputDevices => [const AudioDevice(name: 'Default Speaker (Fallback)', id: 0)];

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission denied');
    }

    final recordStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );

    _isCapturing = true;

    _recordSubscription = recordStream.listen((chunk) {
      if (!_isCapturing) return;

      final byteData = ByteData.sublistView(Uint8List.fromList(chunk));
      final numSamples = byteData.lengthInBytes ~/ 2;
      final doubleSamples = Float64List(numSamples);

      for (int i = 0; i < numSamples; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little);
        doubleSamples[i] = sample / 32768.0;
      }
      _audioStreamController.add(doubleSamples);
    }, onError: (err) {
      print('Fallback capture error: $err');
    });
  }

  @override
  Future<void> stopCapture() async {
    if (!_isCapturing) return;

    await _recordSubscription?.cancel();
    _recordSubscription = null;
    await _recorder.stop();
    _isCapturing = false;
  }

  @override
  Future<void> startPlayback() async {
    _playbackQueue.clear();
    _isPlaying = true;
  }

  @override
  Future<void> stopPlayback() async {
    await _player.stop();
    _isPlaying = false;
    _playbackQueue.clear();
  }

  @override
  Future<void> enqueueForPlayback(Float64List samples) async {
    if (!_isPlaying) return;

    _playbackQueue.addAll(samples);

    // If queue reaches critical size or at normal block size, render and play it
    if (_playbackQueue.length >= 8192) {
      final chunk = Float64List.fromList(_playbackQueue);
      _playbackQueue.clear();

      final wavBytes = WavUtility.createWav(chunk, 44100);
      await _player.play(BytesSource(wavBytes));
    }
  }
}

// WAV utility for converting raw float PCM streams into standard 16-bit mono PCM WAV bytes.
class WavUtility {
  static Uint8List createWav(Float64List samples, int sampleRate) {
    final numSamples = samples.length;
    final dataSize = numSamples * 2;
    final wavBytes = Uint8List(44 + dataSize);
    final byteData = ByteData.view(wavBytes.buffer);

    // RIFF header
    wavBytes.setRange(0, 4, 'RIFF'.codeUnits);
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    wavBytes.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt chunk
    wavBytes.setRange(12, 16, 'fmt '.codeUnits);
    byteData.setUint32(16, 16, Endian.little); // Chunk size
    byteData.setUint16(20, 1, Endian.little);  // PCM format
    byteData.setUint16(22, 1, Endian.little);  // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    byteData.setUint16(32, 2, Endian.little);  // Block align
    byteData.setUint16(34, 16, Endian.little); // 16 bits per sample

    // data chunk
    wavBytes.setRange(36, 40, 'data'.codeUnits);
    byteData.setUint32(40, dataSize, Endian.little);

    // Data payload
    for (int i = 0; i < numSamples; i++) {
      double s = samples[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      final intSample = (s * 32767.0).round();
      byteData.setInt16(44 + i * 2, intSample, Endian.little);
    }

    return wavBytes;
  }
}

// Generates calibration signals and sine/chirp/silence waveforms
class TestToneGenerator {
  static Float64List generateSine(double frequencyHz, double durationSec, double sampleRate) {
    final numSamples = (durationSec * sampleRate).round();
    final samples = Float64List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      samples[i] = math.sin(2.0 * math.pi * frequencyHz * t);
    }
    return samples;
  }

  static Float64List generateChirp(double f0, double f1, double durationSec, double sampleRate) {
    final numSamples = (durationSec * sampleRate).round();
    final samples = Float64List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final phase = 2.0 * math.pi * (f0 * t + (f1 - f0) / (2.0 * durationSec) * t * t);
      samples[i] = math.sin(phase);
    }
    return samples;
  }

  static Float64List generateSilence(double durationSec, double sampleRate) {
    final numSamples = (durationSec * sampleRate).round();
    return Float64List(numSamples);
  }
}

extension DoubleToFloatExtension on double {
  double toFloat() {
    return this;
  }
}
