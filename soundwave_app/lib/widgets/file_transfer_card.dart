// File transfer card (#89): pick a file (FileGateway / file_picker) and send
// it, show fragment progress for outgoing and incoming transfers, and list
// received files.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/arq.dart';
import '../engine/link_frame.dart';
import '../engine/link_receiver.dart';
import '../engine/transfer_notice.dart';
import '../export/file_gateway.dart';
import '../state/app_state.dart';

class FileTransferCard extends StatefulWidget {
  const FileTransferCard({
    super.key,
    this.gateway = const PlatformFileGateway(),
  });

  /// Platform file picker; injectable for tests.
  final FileGateway gateway;

  @override
  State<FileTransferCard> createState() => _FileTransferCardState();
}

class _FileTransferCardState extends State<FileTransferCard> {
  PickedSignalFile? _selected;
  String? _pickError;

  Future<void> _pick() async {
    try {
      final f = await widget.gateway
          .pickTransferFile(maxBytes: LinkMessage.maxContentBytes);
      if (!mounted || f == null) return;
      setState(() {
        _selected = f;
        _pickError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pickError = '$e');
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tx = state.txTransfer;
    final rx = state.rxTransfer;
    final txActive = tx != null &&
        (tx.state == TxTransferState.sending ||
            tx.state == TxTransferState.retrying);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File Transfer', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _selected == null
                  ? 'No file selected (up to 1 MB)'
                  : '${_selected!.name} (${_size(_selected!.bytes.length)})',
              key: const Key('selected_file_label'),
            ),
            if (_pickError != null)
              Text(
                _pickError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('choose_file_button'),
                  onPressed: txActive ? null : _pick,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose File'),
                ),
                ElevatedButton.icon(
                  key: const Key('send_file_button'),
                  onPressed: _selected == null || txActive
                      ? null
                      : () => state.sendFileBytes(_selected!.bytes,
                          fileName: _selected!.name),
                  icon: const Icon(Icons.upload_file),
                  label:
                      Text(state.arqEnabled ? 'Send File (ARQ)' : 'Send File'),
                ),
                if (txActive)
                  OutlinedButton.icon(
                    onPressed: state.cancelTransfer,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
            if (tx != null) ...[
              const SizedBox(height: 12),
              Text(
                '${tx.fileName ?? 'Message'} (${_size(tx.contentBytes)}): '
                '${tx.fragmentsDone}/${tx.fragmentCount} fragments, '
                '${tx.retransmissions} retransmissions - ${tx.state.name}',
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: tx.fraction),
            ],
            if (state.transferError != null) ...[
              const SizedBox(height: 8),
              Text(
                state.transferError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (rx != null) ...[
              const SizedBox(height: 12),
              Text(
                'Receiving message ${rx.msgId}: '
                '${rx.received}/${rx.count} fragments - ${rx.state.name}'
                '${rx.error != null ? ' (${rx.error})' : ''}',
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: rx.state == RxTransferState.failed ? 0 : rx.fraction,
              ),
            ],
            if (state.receivedFiles.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Received Files', style: theme.textTheme.titleSmall),
              for (final f in state.receivedFiles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(
                    '${f.fileName} (${_size(f.size)}'
                    '${f.transferTime != null && f.transferTime! > Duration.zero ? ', ${formatTransferDuration(f.transferTime!)}' : ''})',
                  ),
                  subtitle: Text(f.savedPath ?? 'Not saved: ${f.error}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
