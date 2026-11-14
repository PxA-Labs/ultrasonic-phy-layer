// Platform file picking and sharing behind an interface, so the export and
// import UI can be tested without platform channels.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import 'signal_importer.dart';

/// A file chosen by the user.
class PickedSignalFile {
  final String name;
  final Uint8List bytes;
  const PickedSignalFile(this.name, this.bytes);
}

abstract class FileGateway {
  const FileGateway();

  /// Lets the user pick a .wav/.pcm/.raw file; null if cancelled.
  Future<PickedSignalFile?> pickSignalFile();

  /// Opens the platform share sheet for [file].
  Future<void> shareFile(File file, {String? text});

  /// Lets the user pick any file of at most [maxBytes] to transmit over the
  /// link layer (#89); null if cancelled. Throws [FormatException] if larger.
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes});
}

/// [FileGateway] backed by `file_picker` and `share_plus`.
class PlatformFileGateway extends FileGateway {
  const PlatformFileGateway();

  @override
  Future<PickedSignalFile?> pickSignalFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import signal',
      type: FileType.custom,
      allowedExtensions: SignalImporter.extensions,
    );
    if (picked == null) return null;
    final length = await picked.length();
    if (length != null && length > SignalImporter.defaultMaxBytes) {
      throw FormatException('File is too large ($length bytes)');
    }
    return PickedSignalFile(picked.name, await picked.readAsBytes());
  }

  @override
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes}) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Send file',
      type: FileType.any,
    );
    if (picked == null) return null;
    final length = await picked.length();
    if (length != null && length > maxBytes) {
      throw FormatException(
          'File is too large ($length bytes, limit $maxBytes)');
    }
    final bytes = await picked.readAsBytes();
    if (bytes.length > maxBytes) {
      throw FormatException(
          'File is too large (${bytes.length} bytes, limit $maxBytes)');
    }
    return PickedSignalFile(picked.name, bytes);
  }

  @override
  Future<void> shareFile(File file, {String? text}) async {
    final params = ShareParams(files: [XFile(file.path)], text: text);
    await SharePlus.instance.share(params);
  }
}
