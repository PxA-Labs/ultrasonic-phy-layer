// Mock classes for testing engine components.

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';

class MockSoundwaveNative implements SoundwaveNative {
  /// When set, both demodulators return these bytes instead of the default
  /// valid frame (e.g. garbage to exercise the frame-error path).
  Uint8List? demodOutput;

  /// Number of demodulate calls (CSS + OFDM).
  int demodCalls = 0;

  /// How many more detectFrame calls report a frame; afterwards detection
  /// fails like the real library does on noise (SW_ERR_SYNC). Unlimited by
  /// default so non-RX tests keep their old behaviour.
  int framesToDetect = 1 << 30;

  /// Default frame: CRC "6" (mock CRC = byte sum of [1, 2, 3]) + payload +
  /// 32 bytes of dummy parity.
  static Uint8List defaultFrame({bool withParity = true}) =>
      Uint8List.fromList([
        6, 0, 0, 0, // CRC of payload (sum of [1, 2, 3] = 6)
        1, 2, 3, // payload
        if (withParity) ...List.filled(32, 0xAA), // parity
      ]);

  /// Mock AGC: multiplies samples by [agcLinearGain] and reports
  /// [agcReportedGainDb]. Set [hasAgc] false to simulate an old library.
  @override
  bool hasAgc = true;
  double agcLinearGain = 1.0;
  double agcReportedGainDb = 6.0;
  int agcCreates = 0, agcProcessCalls = 0, agcDestroys = 0, agcResets = 0;

  @override
  Pointer<Void> agcCreate(int sampleRate, {double targetRms = 0.0}) {
    agcCreates++;
    return Pointer<Void>.fromAddress(0x1000 + agcCreates);
  }

  @override
  void agcProcess(Pointer<Void> handle, Pointer<Float> samples, int len) {
    agcProcessCalls++;
    final v = samples.asTypedList(len);
    for (var i = 0; i < len; i++) {
      v[i] *= agcLinearGain;
    }
  }

  @override
  double agcGainDb(Pointer<Void> handle) => agcReportedGainDb;

  @override
  void agcReset(Pointer<Void> handle) => agcResets++;

  @override
  void agcDestroy(Pointer<Void> handle) => agcDestroys++;

  @override
  String get version => '1.0.0-mock';

  @override
  int crc32(Uint8List data) {
    return data.fold(0, (sum, b) => sum + b);
  }

  @override
  Uint8List rsEncode(Uint8List message) {
    return Uint8List.fromList(List.generate(32, (i) => 0xAA));
  }

  @override
  Map<String, dynamic> rsDecode(Uint8List message, Uint8List parity) {
    return {
      'message': message,
      'errors_corrected': 0,
    };
  }

  @override
  Float32List cssModulate(Uint8List bits, Pointer<SwConfig> config) {
    return Float32List.fromList(List.generate(100, (i) => i.toDouble()));
  }

  @override
  Uint8List cssDemodulate(Float32List samples, Pointer<SwConfig> config) {
    demodCalls++;
    return demodOutput ?? defaultFrame();
  }

  @override
  Float32List ofdmModulate(Uint8List bits, Pointer<SwConfig> config) {
    return Float32List.fromList(List.generate(100, (i) => i.toDouble()));
  }

  @override
  Uint8List ofdmDemodulate(Float32List samples, Pointer<SwConfig> config) {
    demodCalls++;
    return demodOutput ?? defaultFrame();
  }

  @override
  Map<String, dynamic> detectFrame(
      Float32List samples, Pointer<SwConfig> config) {
    if (framesToDetect <= 0) throw SwException(-4);
    framesToDetect--;
    return {
      'frame_start': 0,
      'snr': 15.0,
    };
  }

  @override
  double estimateCfo(Float32List samples, Pointer<SwConfig> config) {
    return 0.0;
  }

  @override
  Pointer<Void> audioCaptureStart(Pointer<SwConfig> config) {
    return Pointer<Void>.fromAddress(0);
  }

  @override
  void audioCaptureStop(Pointer<Void> handle) {}

  @override
  Float32List audioCaptureRead(Pointer<Void> handle, int count) {
    return Float32List(count);
  }

  @override
  Pointer<Void> audioPlaybackStart(Pointer<SwConfig> config) {
    return Pointer<Void>.fromAddress(0);
  }

  @override
  void audioPlaybackStop(Pointer<Void> handle) {}

  @override
  void audioPlaybackWrite(Pointer<Void> handle, Float32List samples) {}
}

class MockAudioService implements AudioService {
  bool isCapturing = false;
  bool isPlaying = false;
  Float64List? playbackQueue;
  void Function()? onPlaybackStarted;
  final StreamController<Float64List> _audioStreamController =
      StreamController<Float64List>.broadcast();

  @override
  Stream<Float64List> get audioStream => _audioStreamController.stream;

  @override
  List<AudioDevice> get inputDevices => [];

  @override
  List<AudioDevice> get outputDevices => [];

  @override
  Future<void> startCapture() async {
    isCapturing = true;
  }

  @override
  Future<void> stopCapture() async {
    isCapturing = false;
  }

  @override
  Future<void> enqueueForPlayback(Float64List samples) async {
    playbackQueue = samples;
  }

  @override
  Future<void> startPlayback() async {
    isPlaying = true;
    onPlaybackStarted?.call();
  }

  @override
  Future<void> stopPlayback() async {
    isPlaying = false;
  }

  @override
  void updateConfig(Map<String, dynamic> config) {}

  void pushMockChunk(Float64List chunk) {
    _audioStreamController.add(chunk);
  }
}
