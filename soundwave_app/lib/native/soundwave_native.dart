// Dart FFI wrappers for all sw_*() C API functions.
// Loads libsoundwave dynamically per-platform and exposes typed Dart methods.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

// C function type definitions
typedef Crc32CNative = Int32 Function(
  Pointer<Uint8> data,
  IntPtr len,
  Pointer<Uint32> crc,
);
typedef Crc32Dart = int Function(
  Pointer<Uint8> data,
  int len,
  Pointer<Uint32> crc,
);

typedef VersionCNative = Pointer<Utf8> Function();
typedef VersionDart = Pointer<Utf8> Function();

typedef RsEncodeCNative = Int32 Function(
  Pointer<Uint8> data,
  IntPtr dataLen,
  Pointer<Uint8> parity,
  Pointer<IntPtr> parityLen,
);
typedef RsEncodeDart = int Function(
  Pointer<Uint8> data,
  int dataLen,
  Pointer<Uint8> parity,
  Pointer<IntPtr> parityLen,
);

typedef RsDecodeCNative = Int32 Function(
  Pointer<Uint8> data,
  Pointer<IntPtr> dataLen,
  Pointer<Uint8> parity,
  IntPtr parityLen,
  Pointer<Int32> errorsCorrected,
);
typedef RsDecodeDart = int Function(
  Pointer<Uint8> data,
  Pointer<IntPtr> dataLen,
  Pointer<Uint8> parity,
  int parityLen,
  Pointer<Int32> errorsCorrected,
);

typedef CssModulateCNative = Int32 Function(
  Pointer<Uint8> bits,
  IntPtr bitLen,
  SwConfig cfg,
  Pointer<Float> samples,
  Pointer<IntPtr> sampleLen,
);
typedef CssModulateDart = int Function(
  Pointer<Uint8> bits,
  int bitLen,
  SwConfig cfg,
  Pointer<Float> samples,
  Pointer<IntPtr> sampleLen,
);

typedef CssDemodulateCNative = Int32 Function(
  Pointer<Float> samples,
  IntPtr sampleLen,
  SwConfig cfg,
  Pointer<Uint8> bits,
  Pointer<IntPtr> bitLen,
);
typedef CssDemodulateDart = int Function(
  Pointer<Float> samples,
  int sampleLen,
  SwConfig cfg,
  Pointer<Uint8> bits,
  Pointer<IntPtr> bitLen,
);

typedef OfdmModulateCNative = Int32 Function(
  Pointer<Uint8> bits,
  IntPtr bitLen,
  SwConfig cfg,
  Pointer<Float> samples,
  Pointer<IntPtr> sampleLen,
);
typedef OfdmModulateDart = int Function(
  Pointer<Uint8> bits,
  int bitLen,
  SwConfig cfg,
  Pointer<Float> samples,
  Pointer<IntPtr> sampleLen,
);

typedef OfdmDemodulateCNative = Int32 Function(
  Pointer<Float> samples,
  IntPtr sampleLen,
  SwConfig cfg,
  Pointer<Uint8> bits,
  Pointer<IntPtr> bitLen,
);
typedef OfdmDemodulateDart = int Function(
  Pointer<Float> samples,
  int sampleLen,
  SwConfig cfg,
  Pointer<Uint8> bits,
  Pointer<IntPtr> bitLen,
);

typedef DetectFrameCNative = Int32 Function(
  Pointer<Float> samples,
  IntPtr len,
  SwConfig cfg,
  Pointer<IntPtr> frameStart,
  Pointer<Float> snr,
);
typedef DetectFrameDart = int Function(
  Pointer<Float> samples,
  int len,
  SwConfig cfg,
  Pointer<IntPtr> frameStart,
  Pointer<Float> snr,
);

typedef EstimateCfoCNative = Int32 Function(
  Pointer<Float> samples,
  IntPtr len,
  SwConfig cfg,
  Pointer<Float> cfoHz,
);
typedef EstimateCfoDart = int Function(
  Pointer<Float> samples,
  int len,
  SwConfig cfg,
  Pointer<Float> cfoHz,
);

typedef AudioCaptureStartCNative = Int32 Function(
  SwConfig cfg,
  Pointer<Pointer<Void>> handle,
);
typedef AudioCaptureStartDart = int Function(
  SwConfig cfg,
  Pointer<Pointer<Void>> handle,
);

typedef AudioCaptureStopCNative = Int32 Function(Pointer<Void> handle);
typedef AudioCaptureStopDart = int Function(Pointer<Void> handle);

typedef AudioCaptureReadCNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Float> buffer,
  IntPtr count,
  Pointer<IntPtr> read,
);
typedef AudioCaptureReadDart = int Function(
  Pointer<Void> handle,
  Pointer<Float> buffer,
  int count,
  Pointer<IntPtr> read,
);

typedef AudioPlaybackStartCNative = Int32 Function(
  SwConfig cfg,
  Pointer<Pointer<Void>> handle,
);
typedef AudioPlaybackStartDart = int Function(
  SwConfig cfg,
  Pointer<Pointer<Void>> handle,
);

typedef AudioPlaybackStopCNative = Int32 Function(Pointer<Void> handle);
typedef AudioPlaybackStopDart = int Function(Pointer<Void> handle);

typedef AudioPlaybackWriteCNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Float> buffer,
  IntPtr count,
);
typedef AudioPlaybackWriteDart = int Function(
  Pointer<Void> handle,
  Pointer<Float> buffer,
  int count,
);

class SoundwaveNative {
  static SoundwaveNative? _instance;
  late final DynamicLibrary _lib;

  late final VersionDart _version;
  late final Crc32Dart _crc32;
  late final RsEncodeDart _rsEncode;
  late final RsDecodeDart _rsDecode;
  late final CssModulateDart _cssModulate;
  late final CssDemodulateDart _cssDemodulate;
  late final OfdmModulateDart _ofdmModulate;
  late final OfdmDemodulateDart _ofdmDemodulate;
  late final DetectFrameDart _detectFrame;
  late final EstimateCfoDart _estimateCfo;
  late final AudioCaptureStartDart _audioCaptureStart;
  late final AudioCaptureStopDart _audioCaptureStop;
  late final AudioCaptureReadDart _audioCaptureRead;
  late final AudioPlaybackStartDart _audioPlaybackStart;
  late final AudioPlaybackStopDart _audioPlaybackStop;
  late final AudioPlaybackWriteDart _audioPlaybackWrite;

  SoundwaveNative._() {
    _lib = _loadLibrary();
    _version = _lib.lookupFunction<VersionCNative, VersionDart>('sw_version');
    _crc32 = _lib.lookupFunction<Crc32CNative, Crc32Dart>('sw_crc32');
    _rsEncode = _lib.lookupFunction<RsEncodeCNative, RsEncodeDart>(
      'sw_rs_encode',
    );
    _rsDecode = _lib.lookupFunction<RsDecodeCNative, RsDecodeDart>(
      'sw_rs_decode',
    );
    _cssModulate = _lib.lookupFunction<CssModulateCNative, CssModulateDart>(
      'sw_css_modulate',
    );
    _cssDemodulate = _lib
        .lookupFunction<CssDemodulateCNative, CssDemodulateDart>(
          'sw_css_demodulate',
        );
    _ofdmModulate = _lib.lookupFunction<OfdmModulateCNative, OfdmModulateDart>(
      'sw_ofdm_modulate',
    );
    _ofdmDemodulate = _lib
        .lookupFunction<OfdmDemodulateCNative, OfdmDemodulateDart>(
          'sw_ofdm_demodulate',
        );
    _detectFrame = _lib.lookupFunction<DetectFrameCNative, DetectFrameDart>(
      'sw_detect_frame',
    );
    _estimateCfo = _lib.lookupFunction<EstimateCfoCNative, EstimateCfoDart>(
      'sw_estimate_cfo',
    );
    _audioCaptureStart = _lib
        .lookupFunction<AudioCaptureStartCNative, AudioCaptureStartDart>(
          'sw_audio_capture_start',
        );
    _audioCaptureStop = _lib
        .lookupFunction<AudioCaptureStopCNative, AudioCaptureStopDart>(
          'sw_audio_capture_stop',
        );
    _audioCaptureRead = _lib
        .lookupFunction<AudioCaptureReadCNative, AudioCaptureReadDart>(
          'sw_audio_capture_read',
        );
    _audioPlaybackStart = _lib
        .lookupFunction<AudioPlaybackStartCNative, AudioPlaybackStartDart>(
          'sw_audio_playback_start',
        );
    _audioPlaybackStop = _lib
        .lookupFunction<AudioPlaybackStopCNative, AudioPlaybackStopDart>(
          'sw_audio_playback_stop',
        );
    _audioPlaybackWrite = _lib
        .lookupFunction<AudioPlaybackWriteCNative, AudioPlaybackWriteDart>(
          'sw_audio_playback_write',
        );
  }

  static SoundwaveNative get instance => _instance ??= SoundwaveNative._();

  static DynamicLibrary _loadLibrary() {
    final searchPaths = [
      if (Platform.isWindows) 'soundwave.dll',
      if (Platform.isMacOS) 'libsoundwave.dylib',
      if (Platform.isLinux) 'libsoundwave.so',
      if (Platform.isMacOS) '../native/build/libsoundwave.dylib',
      if (Platform.isMacOS) '../native/build/asan/libsoundwave.dylib',
      if (Platform.isLinux) '../native/build/libsoundwave.so',
      if (Platform.isWindows) '../native/build/Release/soundwave.dll',
      if (Platform.isWindows) '../native/build/Debug/soundwave.dll',
    ];

    for (final path in searchPaths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Continue to next path
      }
    }

    if (Platform.isAndroid) return DynamicLibrary.open('libsoundwave.so');
    throw UnsupportedError(
      'Could not load native Soundwave library. Searched in: $searchPaths',
    );
  }

  String get version => _version().toDartString();

  int crc32(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    final crcOut = calloc<Uint32>();
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      final ret = _crc32(ptr, data.length, crcOut);
      if (ret != 0) throw SwException(ret);
      return crcOut.value;
    } finally {
      calloc.free(ptr);
      calloc.free(crcOut);
    }
  }

  Uint8List rsEncode(Uint8List message) {
    final msgPtr = calloc<Uint8>(message.length);
    // Allocate 32 parity bytes
    final parityPtr = calloc<Uint8>(32);
    final parityLenPtr = calloc<IntPtr>();
    try {
      msgPtr.asTypedList(message.length).setAll(0, message);
      parityLenPtr.value = 32;
      final ret = _rsEncode(msgPtr, message.length, parityPtr, parityLenPtr);
      if (ret != 0) throw SwException(ret);
      return Uint8List.fromList(parityPtr.asTypedList(parityLenPtr.value));
    } finally {
      calloc.free(msgPtr);
      calloc.free(parityPtr);
      calloc.free(parityLenPtr);
    }
  }

  Map<String, dynamic> rsDecode(Uint8List message, Uint8List parity) {
    final msgPtr = calloc<Uint8>(message.length);
    final msgLenPtr = calloc<IntPtr>();
    final parityPtr = calloc<Uint8>(parity.length);
    final errCorrectedPtr = calloc<Int32>();
    try {
      msgPtr.asTypedList(message.length).setAll(0, message);
      msgLenPtr.value = message.length;
      parityPtr.asTypedList(parity.length).setAll(0, parity);

      final ret = _rsDecode(
        msgPtr,
        msgLenPtr,
        parityPtr,
        parity.length,
        errCorrectedPtr,
      );
      if (ret != 0) throw SwException(ret);

      final decodedMsg = Uint8List.fromList(
        msgPtr.asTypedList(msgLenPtr.value),
      );
      return {'message': decodedMsg, 'errors_corrected': errCorrectedPtr.value};
    } finally {
      calloc.free(msgPtr);
      calloc.free(msgLenPtr);
      calloc.free(parityPtr);
      calloc.free(errCorrectedPtr);
    }
  }

  Float32List cssModulate(Uint8List bits, Pointer<SwConfig> config) {
    final bitsPtr = calloc<Uint8>(bits.length);
    // Allocate double space to prevent overflow
    final samplesCapacity = bits.length * 512;
    final samplesPtr = calloc<Float>(samplesCapacity);
    final samplesLenPtr = calloc<IntPtr>();
    try {
      bitsPtr.asTypedList(bits.length).setAll(0, bits);
      samplesLenPtr.value = samplesCapacity;
      final ret = _cssModulate(
        bitsPtr,
        bits.length,
        config.ref,
        samplesPtr,
        samplesLenPtr,
      );
      if (ret != 0) throw SwException(ret);
      return Float32List.fromList(samplesPtr.asTypedList(samplesLenPtr.value));
    } finally {
      calloc.free(bitsPtr);
      calloc.free(samplesPtr);
      calloc.free(samplesLenPtr);
    }
  }

  Uint8List cssDemodulate(Float32List samples, Pointer<SwConfig> config) {
    final samplesPtr = calloc<Float>(samples.length);
    // Output bits capacity estimation
    final bitsCapacity = samples.length ~/ 16;
    final bitsPtr = calloc<Uint8>(bitsCapacity);
    final bitsLenPtr = calloc<IntPtr>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      bitsLenPtr.value = bitsCapacity;
      final ret = _cssDemodulate(
        samplesPtr,
        samples.length,
        config.ref,
        bitsPtr,
        bitsLenPtr,
      );
      if (ret != 0) throw SwException(ret);
      return Uint8List.fromList(bitsPtr.asTypedList(bitsLenPtr.value));
    } finally {
      calloc.free(samplesPtr);
      calloc.free(bitsPtr);
      calloc.free(bitsLenPtr);
    }
  }

  Float32List ofdmModulate(Uint8List bits, Pointer<SwConfig> config) {
    final bitsPtr = calloc<Uint8>(bits.length);
    final samplesCapacity = bits.length * 1024;
    final samplesPtr = calloc<Float>(samplesCapacity);
    final samplesLenPtr = calloc<IntPtr>();
    try {
      bitsPtr.asTypedList(bits.length).setAll(0, bits);
      samplesLenPtr.value = samplesCapacity;
      final ret = _ofdmModulate(
        bitsPtr,
        bits.length,
        config.ref,
        samplesPtr,
        samplesLenPtr,
      );
      if (ret != 0) throw SwException(ret);
      return Float32List.fromList(samplesPtr.asTypedList(samplesLenPtr.value));
    } finally {
      calloc.free(bitsPtr);
      calloc.free(samplesPtr);
      calloc.free(samplesLenPtr);
    }
  }

  Uint8List ofdmDemodulate(Float32List samples, Pointer<SwConfig> config) {
    final samplesPtr = calloc<Float>(samples.length);
    final bitsCapacity = samples.length ~/ 4;
    final bitsPtr = calloc<Uint8>(bitsCapacity);
    final bitsLenPtr = calloc<IntPtr>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      bitsLenPtr.value = bitsCapacity;
      final ret = _ofdmDemodulate(
        samplesPtr,
        samples.length,
        config.ref,
        bitsPtr,
        bitsLenPtr,
      );
      if (ret != 0) throw SwException(ret);
      return Uint8List.fromList(bitsPtr.asTypedList(bitsLenPtr.value));
    } finally {
      calloc.free(samplesPtr);
      calloc.free(bitsPtr);
      calloc.free(bitsLenPtr);
    }
  }

  Map<String, dynamic> detectFrame(
    Float32List samples,
    Pointer<SwConfig> config,
  ) {
    final samplesPtr = calloc<Float>(samples.length);
    final frameStartPtr = calloc<IntPtr>();
    final snrPtr = calloc<Float>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      final ret = _detectFrame(
        samplesPtr,
        samples.length,
        config.ref,
        frameStartPtr,
        snrPtr,
      );
      if (ret != 0) throw SwException(ret);
      return {'frame_start': frameStartPtr.value, 'snr': snrPtr.value};
    } finally {
      calloc.free(samplesPtr);
      calloc.free(frameStartPtr);
      calloc.free(snrPtr);
    }
  }

  double estimateCfo(Float32List samples, Pointer<SwConfig> config) {
    final samplesPtr = calloc<Float>(samples.length);
    final cfoHzPtr = calloc<Float>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      final ret = _estimateCfo(
        samplesPtr,
        samples.length,
        config.ref,
        cfoHzPtr,
      );
      if (ret != 0) throw SwException(ret);
      return cfoHzPtr.value;
    } finally {
      calloc.free(samplesPtr);
      calloc.free(cfoHzPtr);
    }
  }

  Pointer<Void> audioCaptureStart(Pointer<SwConfig> config) {
    final handlePtr = calloc<Pointer<Void>>();
    try {
      final ret = _audioCaptureStart(config.ref, handlePtr);
      if (ret != 0) throw SwException(ret);
      return handlePtr.value;
    } finally {
      calloc.free(handlePtr);
    }
  }

  void audioCaptureStop(Pointer<Void> handle) {
    final ret = _audioCaptureStop(handle);
    if (ret != 0) throw SwException(ret);
  }

  Float32List audioCaptureRead(Pointer<Void> handle, int count) {
    final bufferPtr = calloc<Float>(count);
    final readPtr = calloc<IntPtr>();
    try {
      final ret = _audioCaptureRead(handle, bufferPtr, count, readPtr);
      if (ret != 0) throw SwException(ret);
      return Float32List.fromList(bufferPtr.asTypedList(readPtr.value));
    } finally {
      calloc.free(bufferPtr);
      calloc.free(readPtr);
    }
  }

  Pointer<Void> audioPlaybackStart(Pointer<SwConfig> config) {
    final handlePtr = calloc<Pointer<Void>>();
    try {
      final ret = _audioPlaybackStart(config.ref, handlePtr);
      if (ret != 0) throw SwException(ret);
      return handlePtr.value;
    } finally {
      calloc.free(handlePtr);
    }
  }

  void audioPlaybackStop(Pointer<Void> handle) {
    final ret = _audioPlaybackStop(handle);
    if (ret != 0) throw SwException(ret);
  }

  void audioPlaybackWrite(Pointer<Void> handle, Float32List samples) {
    final bufferPtr = calloc<Float>(samples.length);
    try {
      bufferPtr.asTypedList(samples.length).setAll(0, samples);
      final ret = _audioPlaybackWrite(handle, bufferPtr, samples.length);
      if (ret != 0) throw SwException(ret);
    } finally {
      calloc.free(bufferPtr);
    }
  }
}
