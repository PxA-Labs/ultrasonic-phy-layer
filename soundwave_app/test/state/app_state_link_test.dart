// AppState link-layer settings and file-send entry points (#89, #100).

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/settings_store.dart';
import '../engine/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ARQ settings default off, sync to the config map and persist',
      () async {
    final store = InMemorySettingsStore();
    final a = AppState(audio: MockAudioService(), store: store);
    expect(a.arqEnabled, isFalse);
    expect(a.configMap['arq_enabled'], isFalse);
    expect(a.configMap['arq_max_retries'], 3);
    expect(a.configMap['arq_ack_timeout_ms'], 500);

    a.setArqEnabled(true);
    a.setArqMaxRetries(5);
    a.setArqAckTimeoutMs(5000); // clamped
    expect(a.arqAckTimeoutMs, 2000);
    await Future<void>.delayed(Duration.zero);

    final b = AppState(audio: MockAudioService(), store: store);
    await b.restoreSettings();
    expect(b.arqEnabled, isTrue);
    expect(b.arqMaxRetries, 5);
    expect(b.arqAckTimeoutMs, 2000);
    expect(b.configMap['arq_ack_timeout_ms'], 2000);
    a.dispose();
    b.dispose();
  });

  test('schema drops out-of-range ARQ values', () {
    final v = ModemSettingsSchema.sanitize({
      'arq_enabled': 'yes',
      'arq_max_retries': 4,
      'arq_ack_timeout_ms': 100,
    });
    expect(v, isEmpty);
    expect(
        ModemSettingsSchema.sanitize({
          'arq_enabled': true,
          'arq_max_retries': 1,
          'arq_ack_timeout_ms': 200,
        }),
        {'arq_enabled': true, 'arq_max_retries': 1, 'arq_ack_timeout_ms': 200});
  });
}
