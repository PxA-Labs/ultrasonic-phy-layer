// File transfer card (#89): send a file by path, show fragment progress for
// outgoing and incoming transfers, and list received files.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/arq.dart';
import '../engine/link_receiver.dart';
import '../state/app_state.dart';

class FileTransferCard extends StatefulWidget {
  const FileTransferCard({super.key});

  @override
  State<FileTransferCard> createState() => _FileTransferCardState();
}

class _FileTransferCardState extends State<FileTransferCard> {
  final _path = TextEditingController();

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
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
            TextField(
              key: const Key('file_path_field'),
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'File path (up to 1 MB)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('send_file_button'),
                  onPressed: _path.text.trim().isEmpty || txActive
                      ? null
                      : () => state.sendFile(_path.text),
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
                  title: Text('${f.fileName} (${_size(f.size)})'),
                  subtitle: Text(f.savedPath ?? 'Not saved: ${f.error}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
