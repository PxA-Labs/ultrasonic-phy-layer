// Widget tests for MicPermissionGate (Android first-launch permission flow).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/services/mic_permission.dart';
import 'package:soundwave/widgets/mic_permission_gate.dart';

void main() {
  testWidgets('renders its child and shows no dialog when disabled',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MicPermissionGate(enabled: false, child: Text('shell')),
    ));
    await tester.pump();

    expect(find.text('shell'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('no runtime permission is needed on desktop test hosts', () async {
    expect(MicPermission.isRequired, isFalse);
    expect(await MicPermission.isGranted(), isTrue);
    await MicPermission.ensureGranted();
  });
}
