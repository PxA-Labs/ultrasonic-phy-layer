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
      appBar: AppBar(title: const Text('Soundwave')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TxSection(state: state),
          const SizedBox(height: 16),
          _RxSection(state: state),
          const SizedBox(height: 16),
          _MessagesLog(state: state),
        ],
      ),
    );
  }
}

class _TxSection extends StatelessWidget {
  final AppState state;
  const _TxSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transmit', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter message (max 256 chars)',
                border: OutlineInputBorder(),
              ),
              maxLength: 256,
              onChanged: (v) => state.txMessage = v,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: state.txMessage.isEmpty ? null : () {},
              icon: const Icon(Icons.send),
              label: const Text('Send'),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receive', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => state.toggleListening(),
                  child: Text(state.isListening ? 'Stop Listening' : 'Start Listening'),
                ),
                const SizedBox(width: 16),
                Text('SNR: ${state.lastSnr.toStringAsFixed(1)} dB'),
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
            Text('Received Messages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            state.messages.isEmpty
                ? const Text('No messages yet')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.messages.length,
                    itemBuilder: (_, i) => ListTile(
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
