// Whether libsoundwave could be loaded, for the Dashboard's status badge
// (#93). The badge used to be a hard-coded green "Native Loaded" dot.

import 'soundwave_native.dart';

class NativeStatus {
  /// Library version (sw_version) when loaded.
  final String? version;

  /// Why loading failed, when it did.
  final String? error;

  const NativeStatus.loaded(this.version) : error = null;
  const NativeStatus.unavailable(String this.error) : version = null;

  bool get isLoaded => error == null;

  /// Loads (or reuses) the shared [SoundwaveNative] instance.
  static NativeStatus probe() {
    try {
      return NativeStatus.loaded(SoundwaveNative.instance.version);
    } catch (e) {
      return NativeStatus.unavailable('$e');
    }
  }
}
