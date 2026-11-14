// Widget tests for the #33 UI: import/preview/demodulate, recording button,
// export menu and storage card.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/export/file_gateway.dart';
import 'package:soundwave/export/soundwave_storage.dart';
import 'package:soundwave/export/wav_format.dart';
import 'package:soundwave/screens/signal_files.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

class FakeGateway extends FileGateway {
  PickedSignalFile? next;
  final shared = <File>[];

  @override
  Future<PickedSignalFile?> pickSignalFile() async => next;

  @override
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes}) async =>
      next;

  @override
  Future<void> shareFile(File file, {String? text}) async {
    shared.add(file);
  }
}

Widget host(AppState state, Widget child) {
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// Real file I/O cannot complete inside the fake-async test zone: alternate
/// real waiting with pumps until [done] holds.
Future<void> pumpIo(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

String? textOf(WidgetTester tester, Key key) {
  final f = find.byKey(key);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data;
}

void main() {
  late AppState state;
  late FakeGateway gateway;

  setUp(() {
    state = AppState(audio: MockAudioService());
    gateway = FakeGateway();
  });

  testWidgets('import shows signal info, waveform and decodes on request',
      (tester) async {
    final calls = <int>[];
    state.signalDecoder = (samples, config, rate) async {
      calls.add(rate);
      return [
        DecodedMessage(
          text: 'hi there',
          snr: 12.0,
          timestamp: DateTime(2026),
          rawBytes: Uint8List(0),
        ),
      ];
    };
    final x = Float64List(22050);
    x[100] = 0.75;
    gateway.next = PickedSignalFile('capture.wav', encodeWav(x));

    await tester.pumpWidget(host(state, SignalFilesCard(gateway: gateway)));
    expect(find.byKey(const Key('signal_info')), findsNothing);

    await tester.tap(find.byKey(const Key('import_signal_button')));
    await tester.pumpAndSettle();
    expect(find.text('capture.wav'), findsOneWidget);
    final info = tester.widget<Text>(find.byKey(const Key('signal_info')));
    expect(info.data, contains('WAV PCM 16-bit'));
    expect(info.data, contains('44100 Hz'));
    expect(info.data, contains('0.50 s'));
    expect(info.data, contains('peak 0.750'));
    expect(find.byKey(const Key('signal_waveform')), findsOneWidget);

    await tester.tap(find.byKey(const Key('demodulate_button')));
    await tester.pumpAndSettle();
    expect(calls, [44100]);
    final result = find.byKey(const Key('demodulation_result'));
    expect(tester.widget<Text>(result).data, contains('"hi there"'));
    expect(state.messages.first, contains('[file] hi there'));
  });

  testWidgets('invalid file shows an import error', (tester) async {
    gateway.next = PickedSignalFile('bad.wav', Uint8List(8));
    await tester.pumpWidget(host(state, SignalFilesCard(gateway: gateway)));
    await tester.tap(find.byKey(const Key('import_signal_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Import failed'), findsOneWidget);
  });

  testWidgets('record button is enabled only while listening', (tester) async {
    await tester.pumpWidget(host(state, SignalFilesCard(gateway: gateway)));
    final button = find.byKey(const Key('record_button'));
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    expect(find.text('Save Recording'), findsOneWidget);
  });

  testWidgets('export menu is disabled until a message is decoded',
      (tester) async {
    await tester.pumpWidget(host(state, MessageLogActions(gateway: gateway)));
    final menu = find.byKey(const Key('export_messages_menu'));
    expect(
      tester.widget<PopupMenuButton<Object?>>(menu).enabled,
      isFalse,
    );
    final save = find.byKey(const Key('save_signal_sample_button'));
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNull);
  });

  testWidgets('export menu writes the file and opens the share sheet',
      (tester) async {
    final base = Directory.systemTemp.createTempSync('sw_ui_');
    addTearDown(() => base.deleteSync(recursive: true));
    state.storage = SoundwaveStorage(baseDirectory: () async => base);
    state.addDecodedMessage(
      DecodedMessage(
        text: 'logged',
        snr: 5.0,
        timestamp: DateTime(2026),
        rawBytes: Uint8List(0),
      ),
    );
    await tester.pumpWidget(host(state, MessageLogActions(gateway: gateway)));
    await tester.tap(find.byKey(const Key('export_messages_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export All as CSV'));
    await pumpIo(tester, () => gateway.shared.isNotEmpty);
    await tester.pumpAndSettle();
    expect(gateway.shared, hasLength(1));
    final file = gateway.shared.single;
    expect(file.path, endsWith('.csv'));
    expect(file.readAsStringSync(), contains('"logged",5.0,CSS'));
  });

  testWidgets('storage card shows usage and clears after confirmation',
      (tester) async {
    final base = Directory.systemTemp.createTempSync('sw_ui_');
    addTearDown(() => base.deleteSync(recursive: true));
    state.storage = SoundwaveStorage(baseDirectory: () async => base);
    final rec = await tester.runAsync(
      () => state.storage.directory(StorageArea.recordings),
    );
    File('${rec!.path}/r.wav').writeAsBytesSync(Uint8List(2048));

    await tester.pumpWidget(host(state, const StorageCard()));
    const usage = Key('storage_usage');
    await pumpIo(tester, () => textOf(tester, usage) != null);
    expect(textOf(tester, usage), startsWith('2.0 KB used'));

    await tester.tap(find.byKey(const Key('clear_recordings_button')));
    await tester.pumpAndSettle();
    expect(find.text('Clear All Recordings?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_clear_button')));
    await tester.pumpAndSettle();
    bool cleared() => textOf(tester, usage)?.startsWith('0 B') ?? false;
    await pumpIo(tester, cleared);
    expect(File('${rec.path}/r.wav').existsSync(), isFalse);
    expect(textOf(tester, usage), startsWith('0 B used'));
  });
}
