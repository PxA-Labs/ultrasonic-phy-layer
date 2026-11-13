// Runtime microphone permission (Android RECORD_AUDIO, issue #87).
//
// The native capture path opens the mic through miniaudio/AAudio, which fails
// silently without the permission, so it must be granted before capture. The
// request itself goes through the `record` plugin, which is already a
// dependency and declares RECORD_AUDIO in its manifest.

import 'dart:io';

import 'package:record/record.dart';

/// Thrown when capture is started without the microphone permission.
class MicrophonePermissionDenied implements Exception {
  const MicrophonePermissionDenied();

  @override
  String toString() => 'Microphone permission denied';
}

class MicPermission {
  MicPermission._();

  /// Desktop platforms have no runtime microphone permission to request.
  static bool get isRequired => Platform.isAndroid || Platform.isIOS;

  /// Whether the permission is already granted, without prompting.
  static Future<bool> isGranted() => _check(request: false);

  /// Shows the system permission prompt if needed; returns the final state.
  static Future<bool> request() => _check(request: true);

  /// Throws [MicrophonePermissionDenied] unless the permission is granted,
  /// prompting for it first on platforms that need it.
  static Future<void> ensureGranted() async {
    if (!isRequired) return;
    if (!await request()) throw const MicrophonePermissionDenied();
  }

  static Future<bool> _check({required bool request}) async {
    if (!isRequired) return true;
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission(request: request);
    } finally {
      await recorder.dispose();
    }
  }
}
