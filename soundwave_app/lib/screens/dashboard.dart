// Dashboard screen — message input, send, start/stop listening, and received messages log.
// Uses provider to read/write AppState.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/soundwave_theme.dart';
import '../widgets/signal_status_bar.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soundwave Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green, // Native library is loaded
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Native Loaded', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SignalStatusBar(),
          const SizedBox(height: 16),
          _TxSection(state: state),
          const SizedBox(height: 16),
          _RxSection(state: state),
          const SizedBox(height: 16),
          _QuickActionsRow(state: state),
          const SizedBox(height: 16),
          _MessagesLog(state: state),
        ],
      ),
    );
  }
}

class _TxSection extends StatefulWidget {
  final AppState state;
  const _TxSection({required this.state});

  @override
  State<_TxSection> createState() => _TxSectionState();
}

class _TxSectionState extends State<_TxSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transmission Control',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Enter message to transmit (max 256 bytes)',
                border: OutlineInputBorder(),
              ),
              maxLength: 256,
              onChanged: (v) => widget.state.txMessage = v,
            ),
            const SizedBox(height: 8),
            if (widget.state.isTransmitting) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            ElevatedButton.icon(
              onPressed:
                  widget.state.txMessage.isEmpty || widget.state.isTransmitting
                      ? null
                      : () {
                          widget.state.sendCurrentMessage();
                          _controller.clear();
                        },
              icon: const Icon(Icons.send),
              label: const Text('Send / Modulate & Play'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RxSection extends StatelessWidget {
  final AppState state;
  const _RxSection({required this.state});

  Color _getSnrColor(double snr, SignalColors colors) {
    if (snr >= 10.0) return colors.success;
    if (snr >= 3.0) return colors.warning;
    return colors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signal = SignalColors.of(context);
    final snrColor = _getSnrColor(state.lastSnr, signal);
    final listening = state.isListening;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receiver Control',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            // Wrap (not Row) so large text scales reflow instead of
            // overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => state.toggleListening(),
                  icon: Icon(listening ? Icons.stop : Icons.mic),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: listening ? scheme.error : null,
                    foregroundColor: listening ? scheme.onError : null,
                  ),
                  label: Text(listening ? 'Stop Listening' : 'Start Listening'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      listening ? 'Listening...' : 'Idle',
                      style: TextStyle(
                        color: listening ? signal.success : signal.neutral,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (state.messages.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Live region: screen readers announce each new message.
              Semantics(
                key: const Key('rx_live_region'),
                container: true,
                liveRegion: true,
                child: Text('Last received: ${state.messages.first}'),
              ),
            ],
            if (state.isListening) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Estimated SNR: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: snrColor.withValues(
                        alpha: SignalColors.badgeAlpha,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: snrColor),
                    ),
                    child: Text(
                      '${state.lastSnr.toStringAsFixed(1)} dB',
                      style: TextStyle(
                        color: snrColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final AppState state;
  const _QuickActionsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick Actions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => state.emitTestTone(),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Emit 440Hz Tone'),
                ),
                OutlinedButton.icon(
                  onPressed: () => state.emitChirp(),
                  icon: const Icon(Icons.waves),
                  label: const Text('Emit Chirp Preamble'),
                ),
                OutlinedButton.icon(
                  onPressed: () => state.sendPresetMessage('Soundwave Test'),
                  icon: const Icon(Icons.message),
                  label: const Text('Send Preset Message'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesLog extends StatelessWidget {
  final AppState state;
  const _MessagesLog({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Received Messages Log',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'Count: ${state.messages.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            state.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        'No messages decoded yet. Start listening to capture waves!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.messages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: Icon(
                        Icons.arrow_downward,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      title: Text(state.messages[i]),
                      dense: true,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
