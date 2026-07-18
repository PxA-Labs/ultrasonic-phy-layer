// Settings screen — modulation mode, CSS/OFDM parameters, FEC options, audio device selection.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mode selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'CSS', label: Text('CSS')),
              ButtonSegment(value: 'OFDM', label: Text('OFDM')),
            ],
            selected: {state.mode == 0 ? 'CSS' : 'OFDM'},
            onSelectionChanged: (v) => state.setMode(v.first == 'CSS' ? 0 : 1),
          ),
          const SizedBox(height: 16),
          // CSS settings
          if (state.mode == 0) _CssSettings(state: state),
          // OFDM settings
          if (state.mode == 1) _OfdmSettings(state: state),
          const SizedBox(height: 16),
          // Presets
          Row(
            children: [
              OutlinedButton(
                onPressed: () => state.loadPreset('default'),
                child: const Text('Defaults'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => state.loadPreset('long_range'),
                child: const Text('Long Range'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => state.loadPreset('high_speed'),
                child: const Text('High Speed'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CssSettings extends StatelessWidget {
  final AppState state;
  const _CssSettings({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CSS Settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Spreading Factor: ${state.sf}'),
            Slider(
              value: state.sf.toDouble(),
              min: 7, max: 12, divisions: 5,
              label: state.sf.toString(),
              onChanged: (v) => state.setSf(v.toInt()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfdmSettings extends StatelessWidget {
  final AppState state;
  const _OfdmSettings({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OFDM Settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: state.numSubcarriers,
              items: const [256, 512, 1024, 2048].map((v) =>
                DropdownMenuItem(value: v, child: Text('FFT: $v'))).toList(),
              onChanged: (v) => state.setNumSubcarriers(v ?? 256),
            ),
          ],
        ),
      ),
    );
  }
}
