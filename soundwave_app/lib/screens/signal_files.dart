// UI for #33: WAV recording, signal import + offline demodulation, message
// export/share, signal-sample saving and storage management.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/rx_engine.dart';
import '../export/file_gateway.dart';
import '../export/message_exporter.dart';
import '../export/signal_importer.dart';
import '../export/soundwave_storage.dart';
import '../state/app_state.dart';

void _snack(ScaffoldMessengerState messenger, String text) {
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// "Save Signal Sample" and "Export All" actions for the received log.
class MessageLogActions extends StatelessWidget {
  const MessageLogActions({
    super.key,
    this.gateway = const PlatformFileGateway(),
  });

  final FileGateway gateway;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          key: const Key('save_signal_sample_button'),
          onPressed: state.hasRecentAudio ? () => _saveSample(context) : null,
          icon: const Icon(Icons.save_alt),
          label: const Text('Save Signal Sample'),
        ),
        PopupMenuButton<ExportFormat>(
          key: const Key('export_messages_menu'),
          tooltip: 'Export all messages',
          enabled: state.messageRecords.isNotEmpty,
          icon: const Icon(Icons.ios_share),
          onSelected: (format) => _export(context, format),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: ExportFormat.json,
              child: Text('Export All as JSON'),
            ),
            PopupMenuItem(
              value: ExportFormat.csv,
              child: Text('Export All as CSV'),
            ),
            PopupMenuItem(
              value: ExportFormat.text,
              child: Text('Export All as TXT'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, ExportFormat format) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await state.exportMessages(format);
      _snack(messenger, 'Exported to ${file.path}');
      await gateway.shareFile(file, text: 'Soundwave Message Log');
    } catch (e) {
      _snack(messenger, 'Export failed: $e');
    }
  }

  Future<void> _saveSample(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(),
    );
    if (note == null) return;
    try {
      final saved = await state.saveSignalSample(note: note);
      _snack(messenger, 'Signal sample saved to ${saved.wav.path}');
    } catch (e) {
      _snack(messenger, 'Saving signal sample failed: $e');
    }
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Signal Sample'),
      content: TextField(
        key: const Key('signal_sample_note'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
          helperText: 'Saves the last ~10 s of captured audio with metadata',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Recording controls and signal import with preview and demodulation.
class SignalFilesCard extends StatefulWidget {
  const SignalFilesCard({
    super.key,
    this.gateway = const PlatformFileGateway(),
  });

  final FileGateway gateway;

  @override
  State<SignalFilesCard> createState() => _SignalFilesCardState();
}

class _SignalFilesCardState extends State<SignalFilesCard> {
  ImportedSignal? _signal;
  WaveformEnvelope? _envelope;
  List<DecodedMessage>? _decoded;
  String? _error;
  bool _busy = false;

  Future<void> _toggleRecording(AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (state.isRecording) {
        final file = await state.stopRecording();
        if (file != null) _snack(messenger, 'Recording saved: ${file.path}');
      } else {
        await state.startRecording();
      }
    } catch (e) {
      _snack(messenger, 'Recording failed: $e');
    }
  }

  Future<void> _import(AppState state) async {
    setState(() => _error = null);
    try {
      final picked = await widget.gateway.pickSignalFile();
      if (picked == null || !mounted) return;
      final signal = const SignalImporter().parse(
        picked.bytes,
        name: picked.name,
        rawSampleRate: state.sampleRate,
      );
      setState(() {
        _signal = signal;
        _envelope = WaveformEnvelope.compute(signal.samples, 256);
        _decoded = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed: $e');
    }
  }

  Future<void> _demodulate(AppState state, ImportedSignal signal) async {
    setState(() {
      _busy = true;
      _error = null;
      _decoded = null;
    });
    try {
      final decoded = await state.decodeImportedSignal(signal);
      if (mounted) setState(() => _decoded = decoded);
    } catch (e) {
      if (mounted) setState(() => _error = 'Demodulation failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final signal = _signal;
    final last = state.lastRecording;
    final recording = state.isRecording;
    final canRecord = recording || state.isListening;
    final recIcon = recording ? Icons.stop_circle : Icons.fiber_manual_record;
    final recLabel = recording ? 'Stop Recording' : 'Save Recording';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recording & Signal Files',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('record_button'),
                  onPressed: canRecord ? () => _toggleRecording(state) : null,
                  icon: Icon(recIcon),
                  label: Text(recLabel),
                ),
                OutlinedButton.icon(
                  key: const Key('import_signal_button'),
                  onPressed: _busy ? null : () => _import(state),
                  icon: const Icon(Icons.file_open),
                  label: const Text('Import Signal'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (recording)
              Text('Recording to ${state.activeRecordingPath}')
            else if (!state.isListening)
              Text(
                'Start listening to record captured audio to WAV.',
                style: theme.textTheme.bodySmall,
              ),
            if (last != null && !recording)
              Text(
                'Last recording: ${last.path}',
                style: theme.textTheme.bodySmall,
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (signal != null) ..._signalDetails(context, state, signal),
          ],
        ),
      ),
    );
  }

  List<Widget> _signalDetails(
    BuildContext context,
    AppState state,
    ImportedSignal signal,
  ) {
    final theme = Theme.of(context);
    final seconds = signal.duration.inMicroseconds / 1e6;
    final secs = seconds.toStringAsFixed(2);
    final peak = signal.peak.toStringAsFixed(3);
    final info =
        '${signal.format} · ${signal.sampleRate} Hz · $secs s · peak $peak';
    final decoded = _decoded;
    final String? result;
    if (decoded == null) {
      result = null;
    } else if (decoded.isEmpty) {
      result = 'No frames decoded with the current settings.';
    } else {
      final texts = decoded.map((m) => '"${m.text}"').join(', ');
      result = 'Decoded ${decoded.length} message(s): $texts';
    }
    return [
      const Divider(height: 24),
      Text(signal.name, style: theme.textTheme.titleSmall),
      Text(info, key: const Key('signal_info')),
      const SizedBox(height: 8),
      SizedBox(
        height: 64,
        width: double.infinity,
        child: CustomPaint(
          key: const Key('signal_waveform'),
          painter: WaveformPainter(
            _envelope ?? WaveformEnvelope.compute(signal.samples, 256),
            theme.colorScheme.secondary,
          ),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('demodulate_button'),
        onPressed: _busy ? null : () => _demodulate(state, signal),
        icon: const Icon(Icons.play_arrow),
        label: Text('Send for Demodulation (${state.modeName})'),
      ),
      if (_busy) ...[
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
      ],
      if (result != null) ...[
        const SizedBox(height: 8),
        Text(result, key: const Key('demodulation_result')),
      ],
    ];
  }
}

/// Min/max envelope of a signal, one pair per horizontal bin.
class WaveformEnvelope {
  final Float32List mins;
  final Float32List maxs;

  const WaveformEnvelope(this.mins, this.maxs);

  factory WaveformEnvelope.compute(Float64List samples, int bins) {
    final n = samples.isEmpty ? 0 : math.min(bins, samples.length);
    final mins = Float32List(n);
    final maxs = Float32List(n);
    for (var b = 0; b < n; b++) {
      final start = b * samples.length ~/ n;
      final end = (b + 1) * samples.length ~/ n;
      var lo = samples[start];
      var hi = samples[start];
      for (var i = start + 1; i < end; i++) {
        lo = math.min(lo, samples[i]);
        hi = math.max(hi, samples[i]);
      }
      mins[b] = lo;
      maxs[b] = hi;
    }
    return WaveformEnvelope(mins, maxs);
  }

  int get length => mins.length;
}

class WaveformPainter extends CustomPainter {
  WaveformPainter(this.envelope, this.color);

  final WaveformEnvelope envelope;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final axis = Paint();
    axis.color = color.withAlpha(80);
    axis.strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), axis);
    final n = envelope.length;
    if (n == 0) return;
    final paint = Paint();
    paint.color = color;
    paint.strokeWidth = math.max(1.0, size.width / n);
    for (var b = 0; b < n; b++) {
      final x = (b + 0.5) * size.width / n;
      final top = mid - envelope.maxs[b].clamp(-1.0, 1.0) * mid;
      final bottom = mid - envelope.mins[b].clamp(-1.0, 1.0) * mid;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.envelope != envelope || oldDelegate.color != color;
}

/// Settings card: storage usage and clearing recordings/exports/samples.
class StorageCard extends StatefulWidget {
  const StorageCard({super.key});

  @override
  State<StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<StorageCard> {
  late Future<Map<StorageArea, int>> _usage;

  @override
  void initState() {
    super.initState();
    _usage = _loadUsage();
  }

  Future<Map<StorageArea, int>> _loadUsage() async {
    final storage = context.read<AppState>().storage;
    return {
      for (final area in StorageArea.values)
        area: await storage.usageBytes(area),
    };
  }

  void _refresh() {
    final usage = _loadUsage();
    setState(() {
      _usage = usage;
    });
  }

  Future<void> _confirmClear(StorageArea area, String label) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear All $label?'),
        content: Text(
          'This permanently deletes every file in ${area.folder}/.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_clear_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final active = state.activeRecordingPath;
      final deleted = await state.storage.clear(
        area,
        keep: {if (active != null) active},
      );
      _snack(messenger, 'Deleted $deleted file(s) from ${area.folder}/');
    } catch (e) {
      _snack(messenger, 'Clearing ${area.folder}/ failed: $e');
    }
    if (mounted) _refresh();
  }

  Widget _clearButton(StorageArea area, String label) {
    return OutlinedButton(
      key: Key('clear_${area.folder}_button'),
      onPressed: () => _confirmClear(area, label),
      child: Text('Clear All $label'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<StorageArea, int>>(
              future: _usage,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Text('Storage usage unavailable');
                }
                final usage = snap.data;
                if (usage == null) return const Text('Calculating usage…');
                final total = usage.values.fold(0, (a, b) => a + b);
                final parts = [
                  for (final e in usage.entries)
                    '${e.key.folder} ${formatBytes(e.value)}',
                ];
                return Text(
                  '${formatBytes(total)} used (${parts.join(', ')})',
                  key: const Key('storage_usage'),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _clearButton(StorageArea.recordings, 'Recordings'),
                _clearButton(StorageArea.exports, 'Exports'),
                _clearButton(StorageArea.samples, 'Samples'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
