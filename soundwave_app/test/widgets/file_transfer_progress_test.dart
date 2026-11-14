// FileTransferCard progress UI (#89, #34): TX/RX progress lines, the Cancel
// button while a transfer is active, transfer errors and the received-files
// list (saved and failed), driven by a state with fixed transfer values.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/link_receiver.dart';
import 'package:soundwave/export/file_gateway.dart';
import 'package:soundwave/services/received_file_store.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/widgets/file_transfer_card.dart';

import '../engine/mock_native.dart';

class NoPickGateway extends FileGateway {
  @override
  Future<PickedSignalFile?> pickSignalFile() async => null;
  @override
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes}) async =>
      null;
  @override
  Future<void> shareFile(File file, {String? text}) async {}
}

class TransferState extends AppState {
  TxTransferProgress? tx;
  RxTransferProgress? rx;
  String? error;
  bool arq = false;
  List<ReceivedFileRecord> files = [];
  int cancels = 0;

  TransferState() : super(audio: MockAudioService());

  @override
  TxTransferProgress? get txTransfer => tx;
  @override
  RxTransferProgress? get rxTransfer => rx;
  @override
  String? get transferError => error;
  @override
  bool get arqEnabled => arq;
  @override
  List<ReceivedFileRecord> get receivedFiles => files;
  @override
  void cancelTransfer() => cancels++;

  void changed() => notifyListeners();
}

TxTransferProgress txProgress(TxTransferState s,
        {int done = 2, int retx = 0, int bytes = 2048, String? name}) =>
    TxTransferProgress(
      msgId: 7,
      fragmentsDone: done,
      fragmentCount: 4,
      retransmissions: retx,
      state: s,
      contentBytes: bytes,
      fileName: name,
    );

void main() {
  late TransferState state;

  setUp(() => state = TransferState());
  tearDown(() => state.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FileTransferCard(gateway: NoPickGateway()),
          ),
        ),
      ),
    ));
    state.changed();
    await tester.pump();
  }

  double? barValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value;

  Finder button(String key) => find.byKey(Key(key));
  bool enabled(WidgetTester tester, String key) {
    final w = tester.widget<ButtonStyleButton>(button(key));
    return w.onPressed != null;
  }

  testWidgets('active transfer: progress, buttons locked, Cancel works',
      (tester) async {
    state.tx = txProgress(TxTransferState.sending, name: 'photo.jpg');
    await pump(tester);

    const line = 'photo.jpg (2.0 KB): 2/4 fragments, 0 retransmissions';
    expect(find.text('$line - sending'), findsOneWidget);
    expect(barValue(tester), 0.5);
    expect(enabled(tester, 'choose_file_button'), isFalse);
    expect(enabled(tester, 'send_file_button'), isFalse);

    await tester.tap(find.text('Cancel'));
    expect(state.cancels, 1);
  });

  testWidgets('retrying counts as active and shows retransmissions',
      (tester) async {
    state.tx = txProgress(TxTransferState.retrying, retx: 3, done: 1);
    await pump(tester);
    const line = 'Message (2.0 KB): 1/4 fragments, 3 retransmissions';
    expect(find.text('$line - retrying'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('finished transfer unlocks the picker and hides Cancel',
      (tester) async {
    for (final s in [
      TxTransferState.completed,
      TxTransferState.failed,
      TxTransferState.cancelled,
    ]) {
      state.tx = txProgress(s, done: 4, bytes: 3 * 1024 * 1024);
      await pump(tester);
      expect(find.text('Cancel'), findsNothing, reason: s.name);
      expect(enabled(tester, 'choose_file_button'), isTrue, reason: s.name);
      expect(find.textContaining('(3.00 MB): 4/4 fragments'), findsOneWidget);
      expect(find.textContaining(s.name), findsOneWidget);
    }
  });

  testWidgets('ARQ label and transfer error', (tester) async {
    state.arq = true;
    state.error = 'TimeoutException: no ACK for fragment 2';
    await pump(tester);
    expect(find.text('Send File (ARQ)'), findsOneWidget);
    final err = tester.widget<Text>(find.text(state.error!));
    final card = tester.element(find.byType(FileTransferCard));
    expect(err.style?.color, Theme.of(card).colorScheme.error);
  });

  testWidgets('RX progress, including a failed reassembly', (tester) async {
    const line = 'Receiving message 12: 3/4 fragments';
    state.rx = const RxTransferProgress(
        src: 0x0A0A,
        msgId: 12,
        received: 3,
        count: 4,
        state: RxTransferState.receiving);
    await pump(tester);
    expect(find.text('$line - receiving'), findsOneWidget);
    expect(barValue(tester), 0.75);

    state.rx = const RxTransferProgress(
        src: 0x0A0A,
        msgId: 12,
        received: 3,
        count: 4,
        state: RxTransferState.failed,
        error: 'CRC mismatch');
    await pump(tester);
    expect(find.text('$line - failed (CRC mismatch)'), findsOneWidget);
    expect(barValue(tester), 0);
  });

  testWidgets('received files list shows saved and unsaved files',
      (tester) async {
    final t = DateTime(2026, 1, 2, 3, 4, 5);
    state.files = [
      ReceivedFileRecord(
          fileName: 'notes.txt',
          mimeType: 'text/plain',
          size: 512,
          timestamp: t,
          savedPath: '/data/received/notes.txt'),
      ReceivedFileRecord(
          fileName: 'big.bin',
          mimeType: 'application/octet-stream',
          size: 5000,
          timestamp: t,
          error: 'disk full'),
    ];
    await pump(tester);
    expect(find.text('Received Files'), findsOneWidget);
    expect(find.text('notes.txt (512 B)'), findsOneWidget);
    expect(find.text('/data/received/notes.txt'), findsOneWidget);
    expect(find.text('big.bin (4.9 KB)'), findsOneWidget);
    expect(find.text('Not saved: disk full'), findsOneWidget);
  });
}
