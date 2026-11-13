// Saves files received over the link layer (#89).
//
// File names arrive from the air and are untrusted: [sanitizeFileName] strips
// directories and unusual characters so a sender cannot write outside the
// receive folder or overwrite an existing file.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

abstract class ReceivedFileSink {
  /// Stores [data] under a name derived from [fileName]; returns where.
  Future<String> save(String fileName, Uint8List data);
}

/// Reduces an untrusted file name to a safe base name.
String sanitizeFileName(String name) {
  var base = name.split(RegExp(r'[/\\]')).last;
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
  base = base.replaceFirst(RegExp(r'^\.+'), '');
  if (base.length > 100) {
    final dot = base.lastIndexOf('.');
    final ext = dot > 0 && base.length - dot <= 10 ? base.substring(dot) : '';
    base = base.substring(0, 100 - ext.length) + ext;
  }
  return base.isEmpty ? 'received.bin' : base;
}

/// Writes into [directory] (default: `<app documents>/Soundwave/received`),
/// never overwriting: `a.txt`, `a (1).txt`, `a (2).txt`, ...
class DirectoryFileSink implements ReceivedFileSink {
  final Future<Directory> Function() _directory;

  DirectoryFileSink({Future<Directory> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(
        '${docs.path}${Platform.pathSeparator}Soundwave'
        '${Platform.pathSeparator}received');
  }

  @override
  Future<String> save(String fileName, Uint8List data) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final safe = sanitizeFileName(fileName);
    final dot = safe.lastIndexOf('.');
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    for (var n = 0; n < 1000; n++) {
      final candidate = n == 0 ? safe : '$stem ($n)$ext';
      final file = File('${dir.path}${Platform.pathSeparator}$candidate');
      try {
        // Exclusive create: fails if the name is taken (no TOCTOU race).
        await file.create(exclusive: true);
      } on FileSystemException {
        continue;
      }
      await file.writeAsBytes(data, flush: true);
      return file.path;
    }
    throw FileSystemException('no free file name', '${dir.path}/$safe');
  }
}

/// A received file as shown in the UI.
class ReceivedFileRecord {
  final String fileName;
  final String mimeType;
  final int size;
  final DateTime timestamp;

  /// Where it was saved, or null if saving failed (see [error]).
  final String? savedPath;
  final String? error;

  const ReceivedFileRecord({
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.timestamp,
    this.savedPath,
    this.error,
  });
}

/// Best-effort MIME type from a file extension (sent with the file).
String mimeTypeForFileName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  const types = {
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'wav': 'audio/wav',
    'zip': 'application/zip',
  };
  return types[ext] ?? 'application/octet-stream';
}
