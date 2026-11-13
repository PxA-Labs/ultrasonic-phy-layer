// AppState integration of WAV recording, message export, signal samples and
// imported-signal decoding (#33).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/export/message_exporter.dart';
import 'package:soundwave/export/signal_importer.dart';
import 'package:soundwave/export/soundwave_storage.dart';
import 'package:soundwave/export/wav_format.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

DecodedMessage decoded(String text, double snr) => DecodedMessage(
      text: text,
      snr: snr,
      timestamp: DateTime.utc(2026, 7, 19, 12),
      rawBytes: Uint8List.fromList(utf8.encode(text)),
    );

void main() {
  late Directory base;
  late MockAudioService audio;
  late AppState state;

  setUp(() {
    base = Directory.systemTemp.createTempSync('sw_state_');
    audio = MockAudioService();
    state = AppState(audio: audio);
    state.storage = SoundwaveStorage(baseDirectory: () async => base);
  });

  tearDown(() {
    state.dispose();
    base.deleteSync(recursive: true);
  });

  /// Lets broadcast-stream deliveries and file writes settle.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('records captured audio to a finalised WAV in recordings/', () async {
    final path = await state.startRecording();
    expect(state.isRecording, isTrue);
    expect(state.activeRecordingPath, path);
    expect(path, contains('recordings'));
    expect(path, matches(RegExp(r'soundwave_recording_\d{8}_\d{6}\.wav$')));

    final chunk1 = Float64List.fromList([0.5, -0.5, 0.25]);
    final chunk2 = Float64List.fromList([0.125, 0.0]);
    audio.pushMockChunk(chunk1);
    audio.pushMockChunk(chunk2);
    await settle();
    expect(state.recordingDuration.inMicroseconds, greaterThan(0));

    final file = await state.stopRecording();
    expect(state.isRecording, isFalse);
    expect(state.lastRecording?.path, path);
    audio.pushMockChunk(Float64List.fromList([0.9])); // after stop: ignored
    await settle();

    final wav = parseWav(file!.readAsBytesSync());
    expect(wav.sampleRate, 44100);
    expect(wav.samples, [0.5, -0.5, 0.25, 0.125, 0.0]);
    expect(await state.stopRecording(), isNull);
  });

  test('a second recording cannot start while one is running', () async {
    await state.startRecording();
    await expectLater(state.startRecording(), throwsStateError);
    await state.stopRecording();
  });

  test('stopping listening finalises an active recording', () async {
    state.toggleListening();
    await state.startRecording();
    audio.pushMockChunk(Float64List.fromList([0.25]));
    await settle();
    state.toggleListening();
    expect(state.isRecording, isFalse);
    for (var i = 0; i < 100 && state.lastRecording == null; i++) {
      await settle();
    }
    final wav = parseWav(state.lastRecording!.readAsBytesSync());
    expect(wav.samples, [0.25]);
  });

  test('decoded messages keep mode and export oldest first', () async {
    state.addDecodedMessage(decoded('first', 10.0));
    state.setMode(1);
    state.addDecodedMessage(decoded('second', 7.5));
    expect(state.messages, hasLength(2));
    expect(state.messageRecords.map((r) => r.mode), ['OFDM', 'CSS']);

    final file = await state.exportMessages(ExportFormat.json);
    expect(file.path, contains('exports'));
    final json = jsonDecode(file.readAsStringSync()) as List;
    expect(json.map((e) => e['text']), ['first', 'second']);
    expect(json.map((e) => e['mode']), ['CSS', 'OFDM']);

    final csv = await state.exportMessages(ExportFormat.csv);
    expect(csv.readAsStringSync(), contains('"second",7.5,OFDM'));
    final txt = await state.exportMessages(ExportFormat.text);
    expect(txt.readAsStringSync(), contains('first (SNR: 10.0 dB, CSS)'));
  });

  test('message records are capped at 100', () {
    for (var i = 0; i < 105; i++) {
      state.addDecodedMessage(decoded('m$i', 1.0));
    }
    expect(state.messageRecords, hasLength(100));
    expect(state.messageRecords.first.text, 'm104');
  });

  test('saves recent capture audio with metadata of the last message',
      () async {
    expect(state.hasRecentAudio, isFalse);
    audio.pushMockChunk(Float64List.fromList([0.5, 0.25]));
    await settle();
    expect(state.hasRecentAudio, isTrue);
    state.addDecodedMessage(decoded('ping', 9.0));

    final saved = await state.saveSignalSample(note: 'desk test');
    expect(saved.wav.path, contains('samples'));
    expect(parseWav(saved.wav.readAsBytesSync()).samples, [0.5, 0.25]);
    final meta = jsonDecode(saved.metadata.readAsStringSync()) as Map;
    expect(meta['note'], 'desk test');
    expect(meta['decoded_text'], 'ping');
    expect(meta['mode'], 'CSS');
    expect(meta['snr'], 9.0);
  });

  test('imported signals are decoded with the current config', () async {
    Map<String, dynamic>? seenConfig;
    int? seenRate;
    Float64List? seenSamples;
    state.setMode(1);
    state.signalDecoder = (samples, config, rate) async {
      seenSamples = samples;
      seenConfig = config;
      seenRate = rate;
      return [decoded('from file', 14.0)];
    };
    final signal = const SignalImporter().parse(
      encodeWav([0.5, -0.5], sampleRate: 48000),
      name: 'x.wav',
    );
    final result = await state.decodeImportedSignal(signal);
    expect(result.single.text, 'from file');
    expect(seenRate, 48000);
    expect(seenSamples, [0.5, -0.5]);
    expect(seenConfig!['modulation'], 1);
    expect(state.messages.first, contains('[file] from file'));
    expect(state.messageRecords.first.mode, 'OFDM');
  });
}
