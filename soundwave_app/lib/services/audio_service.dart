// Audio service abstraction — capture and playback via native C API or platform fallback.

import 'dart:typed_data';

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
}

// TODO: implement NativeAudioService using SoundwaveNative C API
// TODO: implement RecordAudioService using record/audioplayers packages
