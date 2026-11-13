// App storage layout for recordings, exports and saved signal samples:
// `$appDocDir/soundwave/{recordings,exports,samples}/`.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum StorageArea {
  recordings('recordings'),
  exports('exports'),
  samples('samples');

  const StorageArea(this.folder);
  final String folder;
}

class SoundwaveStorage {
  /// [baseDirectory] defaults to the application documents directory; tests
  /// pass a temporary directory.
  SoundwaveStorage({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDirectory;

  /// `<base>/soundwave`
  Future<Directory> root() async {
    final base = await _baseDirectory();
    return Directory('${base.path}${Platform.pathSeparator}soundwave');
  }

  /// The directory for [area], created if missing.
  Future<Directory> directory(StorageArea area) async {
    final r = await root();
    final dir = Directory('${r.path}${Platform.pathSeparator}${area.folder}');
    await dir.create(recursive: true);
    return dir;
  }

  /// Bytes used by [area], or by all areas when [area] is null.
  Future<int> usageBytes([StorageArea? area]) async {
    var total = 0;
    for (final a in area == null ? StorageArea.values : [area]) {
      final r = await root();
      final dir = Directory('${r.path}${Platform.pathSeparator}${a.folder}');
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    }
    return total;
  }

  /// Deletes every file in [area] except paths in [keep] (e.g. a recording
  /// that is still being written). Returns the number of files deleted.
  Future<int> clear(StorageArea area, {Set<String> keep = const {}}) async {
    final r = await root();
    final dir = Directory('${r.path}${Platform.pathSeparator}${area.folder}');
    if (!await dir.exists()) return 0;
    final keepPaths = keep.map((p) => File(p).absolute.path).toSet();
    var deleted = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File || keepPaths.contains(e.absolute.path)) continue;
      await e.delete();
      deleted++;
    }
    return deleted;
  }
}

/// Human-readable size, e.g. `1.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1)} ${units[i]}';
}
