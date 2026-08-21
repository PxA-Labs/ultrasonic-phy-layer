// Mock classes for testing engine components.

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';

class MockSoundwaveNative implements SoundwaveNative {
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
    // Returns dummy CRC (4 bytes of 0x00) + payload + dummy parity (32 bytes of 0xAA)
    final list = <int>[];
    list.addAll([6, 0, 0, 0]); // CRC of payload (sum of [1, 2, 3] = 6)
    list.addAll([1, 2, 3]); // payload
    list.addAll(List.generate(32, (i) => 0xAA)); // Parity
    return Uint8List.fromList(list);
  }

  @override
  Float32List ofdmModulate(Uint8List bits, Pointer<SwConfig> config) {
    return Float32List.fromList(List.generate(100, (i) => i.toDouble()));
  }

  @override
  Uint8List ofdmDemodulate(Float32List samples, Pointer<SwConfig> config) {
    final list = <int>[];
    list.addAll([6, 0, 0, 0]);
    list.addAll([1, 2, 3]);
    list.addAll(List.generate(32, (i) => 0xAA));
    return Uint8List.fromList(list);
  }

  @override
  Map<String, dynamic> detectFrame(
      Float32List samples, Pointer<SwConfig> config) {
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
