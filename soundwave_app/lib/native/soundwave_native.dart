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

typedef EqSymbolsCNative = Int32 Function(
  Pointer<Float> samples,
  IntPtr sampleLen,
  SwConfig cfg,
  Pointer<Float> iq,
  Pointer<IntPtr> numPoints,
);
typedef EqSymbolsDart = int Function(
  Pointer<Float> samples,
  int sampleLen,
  SwConfig cfg,
  Pointer<Float> iq,
  Pointer<IntPtr> numPoints,
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

// AGC (issue #92)
typedef AgcCreateCNative = Int32 Function(
    Int32 sampleRate, Float targetRms, Pointer<Pointer<Void>> handle);
typedef AgcCreateDart = int Function(
    int sampleRate, double targetRms, Pointer<Pointer<Void>> handle);
typedef AgcProcessCNative = Int32 Function(
    Pointer<Void> handle, Pointer<Float> samples, IntPtr len);
typedef AgcProcessDart = int Function(
    Pointer<Void> handle, Pointer<Float> samples, int len);
typedef AgcGainDbCNative = Int32 Function(
    Pointer<Void> handle, Pointer<Float> gainDb);
typedef AgcGainDbDart = int Function(
    Pointer<Void> handle, Pointer<Float> gainDb);
typedef AgcHandleCNative = Int32 Function(Pointer<Void> handle);
typedef AgcHandleDart = int Function(Pointer<Void> handle);

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
    _cssDemodulate =
        _lib.lookupFunction<CssDemodulateCNative, CssDemodulateDart>(
      'sw_css_demodulate',
    );
    _ofdmModulate = _lib.lookupFunction<OfdmModulateCNative, OfdmModulateDart>(
      'sw_ofdm_modulate',
    );
    _ofdmDemodulate =
        _lib.lookupFunction<OfdmDemodulateCNative, OfdmDemodulateDart>(
      'sw_ofdm_demodulate',
    );
    _detectFrame = _lib.lookupFunction<DetectFrameCNative, DetectFrameDart>(
      'sw_detect_frame',
    );
    _estimateCfo = _lib.lookupFunction<EstimateCfoCNative, EstimateCfoDart>(
      'sw_estimate_cfo',
    );
    _audioCaptureStart =
        _lib.lookupFunction<AudioCaptureStartCNative, AudioCaptureStartDart>(
      'sw_audio_capture_start',
    );
    _audioCaptureStop =
        _lib.lookupFunction<AudioCaptureStopCNative, AudioCaptureStopDart>(
      'sw_audio_capture_stop',
    );
    _audioCaptureRead =
        _lib.lookupFunction<AudioCaptureReadCNative, AudioCaptureReadDart>(
      'sw_audio_capture_read',
    );
    _audioPlaybackStart =
        _lib.lookupFunction<AudioPlaybackStartCNative, AudioPlaybackStartDart>(
      'sw_audio_playback_start',
    );
    _audioPlaybackStop =
        _lib.lookupFunction<AudioPlaybackStopCNative, AudioPlaybackStopDart>(
      'sw_audio_playback_stop',
    );
    _audioPlaybackWrite =
        _lib.lookupFunction<AudioPlaybackWriteCNative, AudioPlaybackWriteDart>(
      'sw_audio_playback_write',
    );
  }

  static SoundwaveNative get instance => _instance ??= SoundwaveNative._();

  static DynamicLibrary _loadLibrary() {
    // Android: libsoundwave.so is built by Gradle's externalNativeBuild
    // (android/app/build.gradle.kts -> native/CMakeLists.txt) and packaged in
    // the APK under lib/<abi>/, so the dynamic linker finds it by name.
    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open('libsoundwave.so');
      } on ArgumentError catch (e) {
        throw UnsupportedError(
          'Could not load libsoundwave.so from the APK (is the NDK build '
          'enabled for this ABI?): $e',
        );
      }
    }

    // SOUNDWAVE_LIB pins an exact library (CI, sanitizer builds, or when
    // several stale builds exist); it is tried before the relative paths.
    final override = Platform.environment['SOUNDWAVE_LIB'];
    // Packaged desktop builds ship the library inside the app bundle (see
    // soundwave_app/{linux,windows}/CMakeLists.txt and
    // soundwave_app/macos/packaging/embed_native.sh). Resolve it relative to
    // the executable so it is found regardless of the working directory.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final searchPaths = [
      if (override != null && override.isNotEmpty) override,
      if (Platform.isWindows) '$exeDir${sep}soundwave.dll',
      if (Platform.isMacOS) '$exeDir/../Frameworks/libsoundwave.dylib',
      if (Platform.isLinux) '$exeDir/lib/libsoundwave.so',
      if (Platform.isWindows) 'soundwave.dll',
      if (Platform.isMacOS) 'libsoundwave.dylib',
      if (Platform.isLinux) 'libsoundwave.so',
      // native/build is the documented build directory (DEVELOPER_GUIDE,
      // CI); the legacy repo-root build/ is only a fallback so a stale copy
      // there cannot shadow a fresh build.
      if (Platform.isMacOS) '../native/build/libsoundwave.dylib',
      if (Platform.isMacOS) '../native/build/asan/libsoundwave.dylib',
      if (Platform.isLinux) '../native/build/libsoundwave.so',
      // native/CMakeLists.txt sets PREFIX "lib" on every platform, so a
      // plain CMake build on Windows produces libsoundwave.dll.
      if (Platform.isWindows) '../native/build/Release/libsoundwave.dll',
      if (Platform.isWindows) '../native/build/Debug/libsoundwave.dll',
      if (Platform.isWindows) '../native/build/Release/soundwave.dll',
      if (Platform.isWindows) '../native/build/Debug/soundwave.dll',
      if (Platform.isMacOS) '../build/libsoundwave.dylib',
      if (Platform.isLinux) '../build/libsoundwave.so',
      if (Platform.isWindows) '../build/Release/soundwave.dll',
    ];

    for (final path in searchPaths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Continue to next path
      }
    }

    throw UnsupportedError(
      'Could not load native Soundwave library. Searched in: $searchPaths',
    );
  }

  // AGC symbols are resolved lazily so a library built before the AGC module
  // still loads for everything else; callers can check [hasAgc].
  late final AgcCreateDart _agcCreate =
      _lib.lookupFunction<AgcCreateCNative, AgcCreateDart>('sw_agc_create');
  late final AgcProcessDart _agcProcess =
      _lib.lookupFunction<AgcProcessCNative, AgcProcessDart>('sw_agc_process');
  late final AgcGainDbDart _agcGainDb = _lib
      .lookupFunction<AgcGainDbCNative, AgcGainDbDart>('sw_agc_get_gain_db');
  late final AgcHandleDart _agcReset =
      _lib.lookupFunction<AgcHandleCNative, AgcHandleDart>('sw_agc_reset');
  late final AgcHandleDart _agcDestroy =
      _lib.lookupFunction<AgcHandleCNative, AgcHandleDart>('sw_agc_destroy');

  /// Whether the loaded library exports the AGC API.
  bool get hasAgc => _lib.providesSymbol('sw_agc_create');

  /// Creates a native AGC instance ([targetRms] 0 = default 0.25).
  Pointer<Void> agcCreate(int sampleRate, {double targetRms = 0.0}) {
    final handlePtr = calloc<Pointer<Void>>();
    try {
      final ret = _agcCreate(sampleRate, targetRms, handlePtr);
      if (ret != 0) throw SwException(ret);
      return handlePtr.value;
    } finally {
      calloc.free(handlePtr);
    }
  }

  /// Applies AGC in place to [len] floats at [samples] (caller-owned buffer).
  void agcProcess(Pointer<Void> handle, Pointer<Float> samples, int len) {
    final ret = _agcProcess(handle, samples, len);
    if (ret != 0) throw SwException(ret);
  }

  double agcGainDb(Pointer<Void> handle) {
    final out = calloc<Float>();
    try {
      final ret = _agcGainDb(handle, out);
      if (ret != 0) throw SwException(ret);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void agcReset(Pointer<Void> handle) {
    final ret = _agcReset(handle);
    if (ret != 0) throw SwException(ret);
  }

  void agcDestroy(Pointer<Void> handle) {
    final ret = _agcDestroy(handle);
    if (ret != 0) throw SwException(ret);
  }

  // Resolved lazily, like the AGC symbols, so an older library still loads.
  static const _eqSymbolsName = 'sw_ofdm_equalized_symbols';
  late final EqSymbolsDart _eqSymbols =
      _lib.lookupFunction<EqSymbolsCNative, EqSymbolsDart>(_eqSymbolsName);

  /// Whether the loaded library exports [ofdmEqualizedSymbols].
  bool get hasEqualizedSymbols => _lib.providesSymbol(_eqSymbolsName);

  /// Demodulates a frame-aligned OFDM frame and returns its equalized
  /// data-subcarrier points as interleaved I/Q pairs (at most [maxPoints]
  /// points, in symbol order). Throws [SwException] on native errors.
  Float32List ofdmEqualizedSymbols(
    Float32List samples,
    Pointer<SwConfig> config, {
    int maxPoints = 4096,
  }) {
    if (samples.isEmpty || maxPoints <= 0) throw SwException(-1);
    final samplesPtr = calloc<Float>(samples.length);
    final iqPtr = calloc<Float>(2 * maxPoints);
    final countPtr = calloc<IntPtr>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      countPtr.value = maxPoints;
      final ret = _eqSymbols(
        samplesPtr,
        samples.length,
        config.ref,
        iqPtr,
        countPtr,
      );
      if (ret != 0) throw SwException(ret);
      final count = countPtr.value;
      if (count < 0 || count > maxPoints) throw SwException(_errOverflow);
      return Float32List.fromList(iqPtr.asTypedList(2 * count));
    } finally {
      calloc.free(samplesPtr);
      calloc.free(iqPtr);
      calloc.free(countPtr);
    }
  }

  String get version => _version().toDartString();

  int crc32(Uint8List data) {
    if (data.isEmpty) return 0;
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

  /// SW_ERR_OVERFLOW: the output buffer was too small; the API reports the
  /// required size in the length out-parameter.
  static const int _errOverflow = -7;

  /// Upper bound on samples we are willing to allocate for one frame
  /// (~95 s at 44.1 kHz). Guards against absurd sizes from bad configs; the
  /// TX path sizes frames to stay below it (FrameGeometry.txFrameSampleBudget).
  static const int maxFrameSamples = 1 << 22;

  /// Modulates [frame] bytes. The C API counts *bits* (bit_len), so all
  /// frame.length * 8 bits are sent. The output size depends on the config,
  /// so the buffer is sized with the API's own overflow protocol: try a first
  /// estimate, and on SW_ERR_OVERFLOW retry once with the exact length.
  Float32List _modulate(
    int Function(Pointer<Uint8>, int, SwConfig, Pointer<Float>, Pointer<IntPtr>)
        fn,
    Uint8List frame,
    Pointer<SwConfig> config,
  ) {
    if (frame.isEmpty) throw SwException(-1);
    final bitsPtr = calloc<Uint8>(frame.length);
    final lenPtr = calloc<IntPtr>();
    Pointer<Float> samplesPtr = nullptr;
    try {
      bitsPtr.asTypedList(frame.length).setAll(0, frame);
      final bitLen = frame.length * 8;
      var capacity = bitLen * 1024 + 65536;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (capacity <= 0 || capacity > maxFrameSamples) {
          throw SwException(_errOverflow);
        }
        samplesPtr = calloc<Float>(capacity);
        lenPtr.value = capacity;
        final ret = fn(bitsPtr, bitLen, config.ref, samplesPtr, lenPtr);
        if (ret == 0) {
          return Float32List.fromList(samplesPtr.asTypedList(lenPtr.value));
        }
        calloc.free(samplesPtr);
        samplesPtr = nullptr;
        if (ret != _errOverflow || lenPtr.value <= capacity) {
          throw SwException(ret);
        }
        capacity = lenPtr.value;
      }
      throw SwException(_errOverflow);
    } finally {
      calloc.free(bitsPtr);
      calloc.free(lenPtr);
      if (samplesPtr != nullptr) calloc.free(samplesPtr);
    }
  }

  /// Demodulates [samples] into bytes. The capacity passed to C is in *bits*;
  /// one bit per sample is a safe upper bound for both CSS and OFDM.
  Uint8List _demodulate(
    int Function(Pointer<Float>, int, SwConfig, Pointer<Uint8>, Pointer<IntPtr>)
        fn,
    Float32List samples,
    Pointer<SwConfig> config,
  ) {
    if (samples.isEmpty) throw SwException(-1);
    final samplesPtr = calloc<Float>(samples.length);
    final capacityBytes = (samples.length + 7) ~/ 8 + 1;
    final bitsPtr = calloc<Uint8>(capacityBytes);
    final bitsLenPtr = calloc<IntPtr>();
    try {
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      bitsLenPtr.value = capacityBytes * 8;
      final ret =
          fn(samplesPtr, samples.length, config.ref, bitsPtr, bitsLenPtr);
      if (ret != 0) throw SwException(ret);
      final outBytes = bitsLenPtr.value ~/ 8;
      if (outBytes > capacityBytes) throw SwException(_errOverflow);
      return Uint8List.fromList(bitsPtr.asTypedList(outBytes));
    } finally {
      calloc.free(samplesPtr);
      calloc.free(bitsPtr);
      calloc.free(bitsLenPtr);
    }
  }

  Float32List cssModulate(Uint8List frame, Pointer<SwConfig> config) =>
      _modulate(_cssModulate, frame, config);

  Uint8List cssDemodulate(Float32List samples, Pointer<SwConfig> config) =>
      _demodulate(_cssDemodulate, samples, config);

  Float32List ofdmModulate(Uint8List frame, Pointer<SwConfig> config) =>
      _modulate(_ofdmModulate, frame, config);

  Uint8List ofdmDemodulate(Float32List samples, Pointer<SwConfig> config) =>
      _demodulate(_ofdmDemodulate, samples, config);

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
