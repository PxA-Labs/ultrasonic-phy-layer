// Shows a toast when a file transfer finishes (issue #89): file name, size,
// transfer time and effective throughput, or why it failed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/transfer_notice.dart';
import '../state/app_state.dart';

class TransferNoticeListener extends StatefulWidget {
  final Widget child;

  /// Notices to show; defaults to [AppState.transferNotices].
  final Stream<TransferNotice>? notices;

  const TransferNoticeListener({super.key, required this.child, this.notices});

  @override
  State<TransferNoticeListener> createState() => _TransferNoticeListenerState();
}

class _TransferNoticeListenerState extends State<TransferNoticeListener> {
  Stream<TransferNotice>? _source;
  StreamSubscription<TransferNotice>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(TransferNoticeListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribe();
  }

  void _subscribe() {
    final source = widget.notices ?? context.read<AppState>().transferNotices;
    if (identical(source, _source)) return;
    _sub?.cancel();
    _source = source;
    _sub = source.listen(_show);
  }

  void _show(TransferNotice n) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('transfer_notice'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Icon(
              n.ok
                  ? (n.direction == TransferDirection.sent
                      ? Icons.upload_file
                      : Icons.download_done)
                  : Icons.error_outline,
              color: scheme.onInverseSurface,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(n.message)),
          ],
        ),
      ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
