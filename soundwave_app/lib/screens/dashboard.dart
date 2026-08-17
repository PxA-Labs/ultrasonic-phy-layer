// Dashboard screen — message input, send, start/stop listening, and received messages log.
// Uses provider to read/write AppState.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

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
            Text('Transmission Control', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
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
              onPressed: widget.state.txMessage.isEmpty || widget.state.isTransmitting
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

  Color _getSnrColor(double snr) {
    if (snr >= 10.0) return Colors.green;
    if (snr >= 3.0) return Colors.yellow;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receiver Control', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () => state.toggleListening(),
                  icon: Icon(state.isListening ? Icons.stop : Icons.mic),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state.isListening ? Colors.red.shade900 : null,
                  ),
                  label: Text(
                    state.isListening ? 'Stop Listening' : 'Start Listening',
                  ),
                ),
                Row(
                  children: [
                    const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      state.isListening ? 'Listening...' : 'Idle',
                      style: TextStyle(
                        color: state.isListening ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (state.isListening) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Estimated SNR: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, py: 2),
                    decoration: BoxDecoration(
                      color: _getSnrColor(state.lastSnr).withAlpha(50),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _getSnrColor(state.lastSnr)),
                    ),
                    child: Text(
                      '${state.lastSnr.toStringAsFixed(1)} dB',
                      style: TextStyle(
                        color: _getSnrColor(state.lastSnr),
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
            Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
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
                Text(
                  'Received Messages Log',
                  style: Theme.of(context).textTheme.titleMedium,
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
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        'No messages decoded yet. Start listening to capture waves!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.messages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.arrow_downward, color: Colors.cyan),
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
