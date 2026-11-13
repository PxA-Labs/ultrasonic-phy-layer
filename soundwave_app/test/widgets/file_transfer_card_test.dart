// FileTransferCard (#89): file selection goes through the FileGateway.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/export/file_gateway.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/widgets/file_transfer_card.dart';

import '../engine/mock_native.dart';

class FakeTransferGateway extends FileGateway {
  PickedSignalFile? next;
  Object? error;
  int? lastMaxBytes;

  @override
  Future<PickedSignalFile?> pickSignalFile() async => null;

  @override
  Future<PickedSignalFile?> pickTransferFile({required int maxBytes}) async {
    lastMaxBytes = maxBytes;
    final e = error;
    if (e != null) throw e;
    return next;
  }

  @override
  Future<void> shareFile(File file, {String? text}) async {}
}

void main() {
  late AppState state;
  late FakeTransferGateway gateway;

  setUp(() {
    state = AppState(audio: MockAudioService());
    gateway = FakeTransferGateway();
  });
  tearDown(() => state.dispose());

  Widget app() => ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FileTransferCard(gateway: gateway),
            ),
          ),
        ),
      );

  ElevatedButton sendButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byKey(const Key('send_file_button')));

  testWidgets('send is disabled until a file is picked', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('No file selected (up to 1 MB)'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);

    gateway.next = PickedSignalFile('photo.png', Uint8List(2048));
    await tester.tap(find.byKey(const Key('choose_file_button')));
    await tester.pump();

    expect(gateway.lastMaxBytes, LinkMessage.maxContentBytes);
    expect(find.text('photo.png (2.0 KB)'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('cancelled pick keeps the previous state', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('choose_file_button')));
    await tester.pump();
    expect(find.text('No file selected (up to 1 MB)'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('picker errors (e.g. file too large) are shown', (tester) async {
    gateway.error = const FormatException('File is too large');
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('choose_file_button')));
    await tester.pump();
    expect(find.textContaining('File is too large'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
  });
}
