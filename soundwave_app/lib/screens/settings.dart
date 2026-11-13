// Settings screen — modulation mode, CSS/OFDM parameters, FEC options, audio device selection.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'signal_files.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preset Loader Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick Configurations (Presets)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => state.loadPreset('default'),
                        child: const Text('Defaults'),
                      ),
                      OutlinedButton(
                        onPressed: () => state.loadPreset('long_range'),
                        child: const Text('Long Range (Robust)'),
                      ),
                      OutlinedButton(
                        onPressed: () => state.loadPreset('high_speed'),
                        child: const Text('High Speed (OFDM)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Modulation Selector Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modulation Mode',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'CSS',
                            label: Text('CSS (Chirp Spread Spectrum)')),
                        ButtonSegment(
                            value: 'OFDM',
                            label: Text('OFDM (Orthogonal Freq Division)')),
                      ],
                      selected: {state.mode == 0 ? 'CSS' : 'OFDM'},
                      onSelectionChanged: (v) =>
                          state.setMode(v.first == 'CSS' ? 0 : 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Mode-specific configuration card
          if (state.mode == 0) _CssSettingsCard(state: state),
          if (state.mode == 1) _OfdmSettingsCard(state: state),
          const SizedBox(height: 16),

          // FEC Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FEC & Error Correction',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Enable Reed-Solomon Correction'),
                    subtitle:
                        const Text('Uses RS(255,223) error correction layer'),
                    value: state.enableRs,
                    onChanged: (v) => state.setEnableRs(v),
                  ),
                  const Divider(),
                  DropdownButtonFormField<double>(
                    initialValue: state.codingRate,
                    decoration: const InputDecoration(
                        labelText: 'Convolutional Coding Rate'),
                    items: const [
                      DropdownMenuItem(
                          value: 0.5, child: Text('Rate 1/2 (More Robust)')),
                      DropdownMenuItem(
                          value: 0.75, child: Text('Rate 3/4 (Higher Speed)')),
                    ],
                    onChanged: (v) => state.setCodingRate(v ?? 0.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _LinkLayerCard(state: state),
          const SizedBox(height: 16),

          // Audio Hardware & Volume Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audio I/O & Level Controls',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: state.inputDevice?.name,
                    decoration: const InputDecoration(
                        labelText: 'Capture Device (Microphone)'),
                    items: state.inputDevices
                        .map((d) => DropdownMenuItem(
                            value: d.name, child: Text(d.name)))
                        .toList(),
                    onChanged: (val) {
                      final dev =
                          state.inputDevices.firstWhere((d) => d.name == val);
                      state.setInputDevice(dev);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: state.outputDevice?.name,
                    decoration: const InputDecoration(
                        labelText: 'Playback Device (Speaker)'),
                    items: state.outputDevices
                        .map((d) => DropdownMenuItem(
                            value: d.name, child: Text(d.name)))
                        .toList(),
                    onChanged: (val) {
                      final dev =
                          state.outputDevices.firstWhere((d) => d.name == val);
                      state.setOutputDevice(dev);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Playback Volume: ${(state.volume * 100).toInt()}%'),
                  Slider(
                    value: state.volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${(state.volume * 100).toInt()}%',
                    onChanged: (v) => state.setVolume(v),
                  ),
                  SwitchListTile(
                    key: const Key('agc_toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic Gain Control (AGC)'),
                    subtitle: const Text(
                        'Normalises microphone level before decoding '
                        '(-20 to +32 dB). Turn off for manual gain testing.'),
                    value: state.agcEnabled,
                    onChanged: state.setAgcEnabled,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const StorageCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CssSettingsCard extends StatelessWidget {
  final AppState state;
  const _CssSettingsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CSS Modulation Config',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Spreading Factor (SF): ${state.sf}'),
            Slider(
              value: state.sf.toDouble(),
              min: 7,
              max: 12,
              divisions: 5,
              label: 'SF ${state.sf}',
              onChanged: (v) => state.setSf(v.toInt()),
            ),
            const SizedBox(height: 12),
            Text(
                'Chirp/Symbol Duration: ${(state.symbolDuration * 1000).toInt()} ms'),
            Slider(
              value: state.symbolDuration,
              min: 0.01,
              max: 0.1,
              divisions: 9,
              label: '${(state.symbolDuration * 1000).toInt()} ms',
              onChanged: (v) => state.setSymbolDuration(v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: state.carrierFreq.toStringAsFixed(0),
              decoration:
                  const InputDecoration(labelText: 'Carrier Frequency (Hz)'),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (v) =>
                  state.setCarrierFreq(double.tryParse(v) ?? 19000.0),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: state.bandwidth.toStringAsFixed(0),
              decoration:
                  const InputDecoration(labelText: 'Sweep Bandwidth (Hz)'),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (v) =>
                  state.setBandwidth(double.tryParse(v) ?? 2000.0),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfdmSettingsCard extends StatelessWidget {
  final AppState state;
  const _OfdmSettingsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OFDM Modulation Config',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: state.numSubcarriers,
              decoration:
                  const InputDecoration(labelText: 'FFT Subcarriers Size'),
              items: const [256, 512, 1024, 2048]
                  .map((v) =>
                      DropdownMenuItem(value: v, child: Text('FFT Size: $v')))
                  .toList(),
              onChanged: (v) => state.setNumSubcarriers(v ?? 256),
            ),
            const SizedBox(height: 12),
            const Text('Constellation (bits per subcarrier)'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                key: const Key('ofdm_modulation_selector'),
                segments: const [
                  ButtonSegment(value: 0, label: Text('BPSK (robust)')),
                  ButtonSegment(value: 1, label: Text('QPSK (2x rate)')),
                ],
                selected: {state.ofdmModulation},
                onSelectionChanged: (v) => state.setOfdmModulation(v.first),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              // Keyed by FFT size: the options change with it, and a stale
              // selection outside the new item list would assert.
              key: ValueKey('cp_${state.numSubcarriers}'),
              initialValue: AppState.cpOptionsFor(state.numSubcarriers)
                      .contains(state.cpLength)
                  ? state.cpLength
                  : null,
              decoration:
                  const InputDecoration(labelText: 'Cyclic Prefix (CP) Length'),
              items: [
                for (final (i, label) in const [
                  (4, '1/4 of FFT'),
                  (8, '1/8 of FFT'),
                  (16, '1/16 of FFT'),
                ])
                  DropdownMenuItem(
                      value: state.numSubcarriers ~/ i,
                      child: Text('$label (${state.numSubcarriers ~/ i})')),
              ],
              onChanged: (v) =>
                  state.setCpLength(v ?? (state.numSubcarriers ~/ 8)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: state.numPilots,
              decoration:
                  const InputDecoration(labelText: 'Pilot Subcarriers Count'),
              items: const [4, 8, 16, 32, 64]
                  .map((v) =>
                      DropdownMenuItem(value: v, child: Text('$v Pilots')))
                  .toList(),
              onChanged: (v) => state.setNumPilots(v ?? 8),
            ),
            const SizedBox(height: 16),
            const Text('OFDM Channel Equalization Mode'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Zero Forcing (ZF)')),
                  ButtonSegment(
                      value: 1, label: Text('MMSE (Noise Regularised)')),
                ],
                selected: {state.equalizer},
                onSelectionChanged: (v) => state.setEqualizer(v.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Link-layer reliability settings (#100).
class _LinkLayerCard extends StatelessWidget {
  final AppState state;
  const _LinkLayerCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Link Layer & Retransmission (ARQ)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('arq_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic Retransmission (ARQ)'),
              subtitle: const Text(
                  'Wait for an ACK after each fragment and resend on loss. '
                  'Both devices must enable it; turn off for one-way '
                  'broadcast.'),
              value: state.arqEnabled,
              onChanged: state.setArqEnabled,
            ),
            DropdownButtonFormField<int>(
              key: const Key('arq_retries'),
              initialValue: state.arqMaxRetries,
              decoration: const InputDecoration(labelText: 'Max Retries'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 5, child: Text('5')),
              ],
              onChanged: state.arqEnabled
                  ? (v) => state.setArqMaxRetries(v ?? 3)
                  : null,
            ),
            const SizedBox(height: 16),
            Text('ACK Timeout: ${state.arqAckTimeoutMs} ms '
                '(added to frame airtime)'),
            Slider(
              key: const Key('arq_timeout'),
              value: state.arqAckTimeoutMs.toDouble(),
              min: 200,
              max: 2000,
              divisions: 18,
              label: '${state.arqAckTimeoutMs} ms',
              onChanged: state.arqEnabled
                  ? (v) => state.setArqAckTimeoutMs(v.round())
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
