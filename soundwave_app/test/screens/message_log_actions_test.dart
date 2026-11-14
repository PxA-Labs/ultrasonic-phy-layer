// MessageLogActions (#33, #34): the "Save Signal Sample" dialog flow (save,
// cancel, storage failure) and export failures surfacing to the user.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/export/file_gateway.dart';
import 'package:soundwave/export/soundwave_storage.dart';
import 'package:soundwave/screens/signal_files.dart';
import 'package:soundwave/state/app_state.dart';

import '../engine/mock_native.dart';

class FailingShareGateway extends FileGateway {
  @override
  Future<PickedSignalFile?> pickSignalFile() async => null;
  @override
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes}) async =>
      null;
  @override
  Future<void> shareFile(File file, {String? text}) async =>
      throw const FileSystemException('share sheet unavailable');
}

Widget host(AppState state, FileGateway gateway) {
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      home: Scaffold(body: MessageLogActions(gateway: gateway)),
    ),
  );
}

/// Real file I/O cannot complete inside the fake-async test zone: alternate
/// real waiting with pumps until [done] holds. Pumps advance 100 ms so a
/// queued snack bar gets its turn.
Future<void> pumpIo(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets dialog transitions finish (pumpAndSettle is avoided while a text
/// field with a blinking cursor is on screen).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool snackShown(String prefix) =>
    find.textContaining(prefix).evaluate().isNotEmpty;

void main() {
  late AppState state;
  late MockAudioService audio;
  late Directory base;

  setUp(() {
    audio = MockAudioService();
    state = AppState(audio: audio);
    base = Directory.systemTemp.createTempSync('sw_log_');
    state.storage = SoundwaveStorage(baseDirectory: () async => base);
  });
  tearDown(() {
    state.dispose();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  /// Feeds 0.1 s of captured audio so a sample can be saved.
  Future<void> captureSomeAudio(WidgetTester tester) async {
    audio.pushMockChunk(Float64List(4410));
    await tester.pump();
    expect(state.hasRecentAudio, isTrue);
  }

  List<File> savedFiles() => base
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.contains('samples'))
      .toList();

  testWidgets('Save Signal Sample enables once captured audio arrives',
      (tester) async {
    await tester.pumpWidget(host(state, FailingShareGateway()));
    final save = find.byKey(const Key('save_signal_sample_button'));
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNull);

    var notifications = 0;
    state.addListener(() => notifications++);

    // Audio is the only state change: the button must still rebuild.
    audio.pushMockChunk(Float64List(4410));
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNotNull);
    expect(notifications, 1);

    // Further chunks do not change hasRecentAudio, so they do not notify.
    audio.pushMockChunk(Float64List(4410));
    audio.pushMockChunk(Float64List(4410));
    await tester.pump();
    expect(notifications, 1);
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNotNull);
  });

  testWidgets('saving a signal sample writes audio and the note',
      (tester) async {
    await captureSomeAudio(tester);
    await tester.pumpWidget(host(state, FailingShareGateway()));

    final save = find.byKey(const Key('save_signal_sample_button'));
    expect(tester.widget<ButtonStyleButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await settle(tester);
    expect(find.text('Save Signal Sample'), findsWidgets); // dialog title

    await tester.enterText(
        find.byKey(const Key('signal_sample_note')), 'bench test 3 m');
    await tester.tap(find.text('Save'));
    await pumpIo(tester, () => snackShown('Signal sample saved to'));
    expect(find.textContaining('Signal sample saved to'), findsOneWidget);

    final files = savedFiles();
    expect(files.where((f) => f.path.endsWith('.wav')), hasLength(1));
    final sidecars = files.where((f) => !f.path.endsWith('.wav'));
    expect(sidecars, hasLength(1));
    expect(sidecars.single.readAsStringSync(), contains('bench test 3 m'));
  });

  testWidgets('cancelling the dialog saves nothing', (tester) async {
    await captureSomeAudio(tester);
    await tester.pumpWidget(host(state, FailingShareGateway()));
    await tester.tap(find.byKey(const Key('save_signal_sample_button')));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(savedFiles(), isEmpty);
  });

  testWidgets('a storage failure is reported', (tester) async {
    state.storage = SoundwaveStorage(
        baseDirectory: () async => throw const FileSystemException('no disk'));
    await captureSomeAudio(tester);
    await tester.pumpWidget(host(state, FailingShareGateway()));
    await tester.tap(find.byKey(const Key('save_signal_sample_button')));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await pumpIo(tester, () => snackShown('Saving signal sample failed'));
    expect(find.textContaining('no disk'), findsOneWidget);
  });

  testWidgets('a failing share sheet is reported after export', (tester) async {
    state.addDecodedMessage(
      DecodedMessage(
        text: 'logged',
        snr: 5.0,
        timestamp: DateTime(2026),
        rawBytes: Uint8List(0),
      ),
    );
    await tester.pumpWidget(host(state, FailingShareGateway()));
    await tester.tap(find.byKey(const Key('export_messages_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export All as JSON'));
    await pumpIo(tester, () => snackShown('Export failed'));
    expect(find.textContaining('share sheet unavailable'), findsOneWidget);
    // The export itself was written before sharing failed.
    final exports = base
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    expect(exports, hasLength(1));
  });
}
