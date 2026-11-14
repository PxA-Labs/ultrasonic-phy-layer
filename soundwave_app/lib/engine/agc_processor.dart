// AgcProcessor — Dart wrapper around the native AGC (issue #92).
//
// Owns one native AGC instance and a reusable native sample buffer, so a
// 10 ms chunk costs one copy in, one FFI call and one copy out. Recreates the
// instance when the sample rate changes. If the native library predates the
// AGC API (or creation fails) the processor becomes a pass-through rather
// than breaking reception.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:soundwave/native/soundwave_native.dart';

class AgcProcessor {
  final SoundwaveNative _native;

  Pointer<Void> _handle = nullptr;
  int _sampleRate = 0;
  Pointer<Float> _buffer = nullptr;
  int _capacity = 0;
  bool _unavailable = false;
  double _gainDb = 0.0;

  AgcProcessor(this._native);

  /// Last reported gain in dB (0 when bypassed or not yet run).
  double get gainDb => _gainDb;

  /// Whether chunks are actually being gain-controlled.
  bool get isActive => _handle != nullptr;

  bool _ensure(int sampleRate) {
    if (_unavailable) return false;
    if (_handle != nullptr && sampleRate == _sampleRate) return true;
    _releaseHandle();
    try {
      if (!_native.hasAgc) throw StateError('library has no AGC API');
      _handle = _native.agcCreate(sampleRate);
      _sampleRate = sampleRate;
      return true;
    } catch (e) {
      debugPrint('AGC unavailable, bypassing: $e');
      _unavailable = true;
      return false;
    }
  }

  /// Returns the gain-controlled chunk (or [chunk] itself when bypassed).
  Float64List process(Float64List chunk, {required int sampleRate}) {
    if (chunk.isEmpty || !_ensure(sampleRate)) return chunk;
    if (chunk.length > _capacity) {
      if (_buffer != nullptr) calloc.free(_buffer);
      _buffer = calloc<Float>(chunk.length);
      _capacity = chunk.length;
    }
    final view = _buffer.asTypedList(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      view[i] = chunk[i];
    }
    try {
      _native.agcProcess(_handle, _buffer, chunk.length);
      _gainDb = _native.agcGainDb(_handle);
    } catch (e) {
      debugPrint('AGC processing failed, bypassing chunk: $e');
      return chunk;
    }
    final out = Float64List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      out[i] = view[i];
    }
    return out;
  }

  /// Returns the gain to unity (e.g. when listening restarts).
  void reset() {
    _gainDb = 0.0;
    if (_handle == nullptr) return;
    try {
      _native.agcReset(_handle);
    } catch (e) {
      debugPrint('AGC reset failed: $e');
    }
  }

  void _releaseHandle() {
    if (_handle == nullptr) return;
    try {
      _native.agcDestroy(_handle);
    } catch (e) {
      debugPrint('AGC destroy failed: $e');
    }
    _handle = nullptr;
  }

  /// Frees native resources. The processor may be reused afterwards.
  void dispose() {
    _releaseHandle();
    if (_buffer != nullptr) calloc.free(_buffer);
    _buffer = nullptr;
    _capacity = 0;
    _gainDb = 0.0;
  }
}
