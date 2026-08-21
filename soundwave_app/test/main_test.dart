import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/state/app_state.dart';
import 'engine/mock_native.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    await tester.pumpWidget(SoundwaveApp(
      appState: AppState(audio: MockAudioService()),
    ));
    expect(find.text('Soundwave Dashboard'), findsOneWidget);
  });
}
