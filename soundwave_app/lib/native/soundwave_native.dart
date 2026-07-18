// Dart FFI wrappers for all sw_*() C API functions.
// Loads libsoundwave dynamically per-platform and exposes typed Dart methods.

import 'dart:ffi';
import 'dart:io';
import 'bindings.dart';

// C function type definitions
typedef Crc32CNative = Int32 Function(Pointer<Uint8> data, IntPtr len, Pointer<Uint32> crc);
typedef Crc32Dart = int Function(Pointer<Uint8> data, int len, Pointer<Uint32> crc);

typedef VersionCNative = Pointer<Utf8> Function();
typedef VersionDart = Pointer<Utf8> Function();

class SoundwaveNative {
  static SoundwaveNative? _instance;
  late final DynamicLibrary _lib;
  late final Crc32Dart _crc32;
  late final VersionDart _version;

  SoundwaveNative._() {
    _lib = _loadLibrary();
    _crc32 = _lib.lookupFunction<Crc32CNative, Crc32Dart>('sw_crc32');
    _version = _lib.lookupFunction<VersionCNative, VersionDart>('sw_version');
  }

  static SoundwaveNative get instance => _instance ??= SoundwaveNative._();

  static DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) return DynamicLibrary.open('soundwave.dll');
    if (Platform.isMacOS) return DynamicLibrary.open('libsoundwave.dylib');
    if (Platform.isLinux) return DynamicLibrary.open('libsoundwave.so');
    if (Platform.isAndroid) return DynamicLibrary.process();
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  String get version => _version().toDartString();

  int crc32(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    final crcOut = calloc<Uint32>();
    ptr.asTypedList(data.length).setAll(0, data);
    final ret = _crc32(ptr, data.length, crcOut);
    final value = crcOut.value;
    calloc.free(ptr);
    calloc.free(crcOut);
    if (ret != 0) throw SwException(ret);
    return value;
  }
}
