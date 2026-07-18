// Smoke test: main.dart creates app without crashing

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/main.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    await tester.pumpWidget(const SoundwaveApp());
    expect(find.text('Soundwave'), findsOneWidget);
  });
}
