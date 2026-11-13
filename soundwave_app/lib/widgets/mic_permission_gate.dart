// First-launch microphone permission flow (issue #87).
//
// On Android/iOS, explains why the microphone is needed and then shows the
// system prompt. Denial is not fatal: transmit still works, and capture asks
// again (see MicPermission.ensureGranted) when the user starts receiving.

import 'package:flutter/material.dart';

import '../services/mic_permission.dart';

class MicPermissionGate extends StatefulWidget {
  final Widget child;

  /// Overrides platform detection (tests); defaults to
  /// [MicPermission.isRequired].
  final bool? enabled;

  const MicPermissionGate({super.key, required this.child, this.enabled});

  @override
  State<MicPermissionGate> createState() => _MicPermissionGateState();
}

class _MicPermissionGateState extends State<MicPermissionGate> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled ?? MicPermission.isRequired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestIfNeeded());
    }
  }

  Future<void> _requestIfNeeded() async {
    if (await MicPermission.isGranted()) return;
    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.mic),
        title: const Text('Microphone access'),
        content: const Text(
          'Soundwave receives data as near-ultrasonic sound, so it needs the '
          'microphone. Audio is processed on this device and never recorded '
          'or uploaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    final granted = await MicPermission.request();
    if (granted || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Receiving is disabled until microphone access is granted in '
          'system settings.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
