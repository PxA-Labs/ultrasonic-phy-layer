// Settings screen — modulation mode, CSS/OFDM parameters, FEC options, audio device selection.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../onboarding/onboarding_screen.dart';
import '../state/app_state.dart';
import '../state/ui_preferences.dart';

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
                    isExpanded: true,
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
                    isExpanded: true,
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
                    isExpanded: true,
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
                  Semantics(
                    label: 'Playback volume',
                    child: Slider(
                      value: state.volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(state.volume * 100).toInt()}%',
                      onChanged: (v) => state.setVolume(v),
                    ),
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
          const _AppearanceCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Theme mode and tutorial replay (issue #93).
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  /// Null when the screen is hosted without UI preferences, e.g. in
  /// isolated screen tests; the theme selector is then omitted.
  UiPreferences? _maybePrefs(BuildContext context) {
    try {
      return context.watch<UiPreferences>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _openTutorial(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => OnboardingScreen(
          onFinished: () => Navigator.of(route).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _maybePrefs(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance & Help',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (prefs != null) ...[
              const SizedBox(height: 12),
              const Text('Theme'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  key: const Key('theme_mode_selector'),
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {prefs.themeMode},
                  onSelectionChanged: (v) => prefs.setThemeMode(v.first),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ListTile(
              key: const Key('show_tutorial'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.school),
              title: const Text('Show tutorial'),
              subtitle: const Text('Replay the introduction to Soundwave'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openTutorial(context),
            ),
          ],
        ),
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
            Semantics(
              label: 'Spreading factor',
              child: Slider(
                value: state.sf.toDouble(),
                min: 7,
                max: 12,
                divisions: 5,
                label: 'SF ${state.sf}',
                onChanged: (v) => state.setSf(v.toInt()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
                'Chirp/Symbol Duration: ${(state.symbolDuration * 1000).toInt()} ms'),
            Semantics(
              label: 'Chirp symbol duration',
              child: Slider(
                value: state.symbolDuration,
                min: 0.01,
                max: 0.1,
                divisions: 9,
                label: '${(state.symbolDuration * 1000).toInt()} ms',
                onChanged: (v) => state.setSymbolDuration(v),
              ),
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
              isExpanded: true,
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
              isExpanded: true,
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
              isExpanded: true,
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
