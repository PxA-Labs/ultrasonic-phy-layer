// End-to-end app flow (issue #34): first launch -> onboarding -> main shell,
// then a message typed on the dashboard is modulated by the real native DSP,
// "played" into a loopback audio device that feeds the microphone stream,
// detected and demodulated by the receiver, and shown in the UI.
//
// CI runs this on the Linux desktop app under xvfb (flutter-integration job),
// where libsoundwave is the library bundled with the app. Only the sound card
// is replaced (runners have none); everything above it is production code.
//
//   flutter test integration_test -d linux

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soundwave/main.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/onboarding/onboarding_screen.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/state/app_state.dart';
import 'package:soundwave/state/settings_store.dart';
import 'package:soundwave/state/ui_preferences.dart';

/// Audio device whose speaker is wired to its own microphone through a
/// slightly noisy channel, like a phone hearing its own transmission.
class LoopbackAudioService implements AudioService {
  final StreamController<Float64List> _mic =
      StreamController<Float64List>.broadcast();
  final Random _rnd = Random(34);
  Future<void> _channel = Future<void>.value();
  bool _capturing = false;
  int playedSamples = 0;

  @override
  Stream<Float64List> get audioStream => _mic.stream;
  @override
  bool get isCapturing => _capturing;
  @override
  bool get isPlaying => false;
  @override
  List<AudioDevice> get inputDevices => const [];
  @override
  List<AudioDevice> get outputDevices => const [];
  @override
  Future<void> startCapture() async => _capturing = true;
  @override
  Future<void> stopCapture() async => _capturing = false;
  @override
  Future<void> startPlayback() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  void updateConfig(Map<String, dynamic> config) {}

  @override
  Future<void> enqueueForPlayback(Float64List samples) async {
    playedSamples += samples.length;
    final signal = Float64List.fromList(samples);
    // Serialise deliveries so two transmissions never interleave.
    _channel = _channel.then((_) => _deliver(signal));
  }

  /// Feeds [signal] to the microphone in 2048-sample chunks, with 0.1 s of
  /// noise before it and 1 s after it (a live mic keeps delivering audio,
  /// which the receiver needs to finish and confirm a frame).
  Future<void> _deliver(Float64List signal) async {
    const lead = 4410;
    const tail = 44100;
    final x = Float64List(lead + signal.length + tail);
    for (var i = 0; i < x.length; i++) {
      x[i] = (_rnd.nextDouble() * 2 - 1) * 0.005;
    }
    for (var i = 0; i < signal.length; i++) {
      x[lead + i] += signal[i];
    }
    for (var i = 0; i < x.length; i += 2048) {
      if (_mic.isClosed) return;
      final end = min(i + 2048, x.length);
      _mic.add(Float64List.fromList(x.sublist(i, end)));
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Pumps frames for [frames] x 100 ms without pumpAndSettle (the dashboard
/// status dot pulses forever).
Future<void> settle(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Polls [condition] with real time passing (FFI work and audio delivery run
/// between polls) until it holds or 60 s pass.
Future<bool> waitFor(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await tester.runAsync(() => Future<void>.delayed(_pollInterval));
    await tester.pump();
  }
  return true;
}

const _pollInterval = Duration(milliseconds: 100);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding -> dashboard -> message over real DSP loopback',
      (tester) async {
    // The real library must load: this is the point of the test.
    expect(SoundwaveNative.instance, isNotNull);

    final audio = LoopbackAudioService();
    final store = InMemorySettingsStore();
    final state = AppState(audio: audio, store: store);
    state.setMode(1); // OFDM: the fast, well-characterised mode.
    // First launch: nothing persisted yet, so onboarding is due.
    final prefs = UiPreferences(store: InMemorySettingsStore());
    await prefs.restore();
    expect(prefs.isLoaded, isTrue);
    expect(prefs.onboardingComplete, isFalse);

    final app = SoundwaveApp(appState: state, uiPreferences: prefs);
    await tester.pumpWidget(app);
    await settle(tester);

    // --- Onboarding: every page, then "Get started". ---
    expect(find.text(onboardingPages.first.title), findsOneWidget);
    for (var i = 0; i < onboardingPages.length; i++) {
      expect(find.text(onboardingPages[i].title), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_next')));
      await settle(tester);
    }
    expect(prefs.onboardingComplete, isTrue);
    expect(find.text('Soundwave Dashboard'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // --- Receiver on. ---
    await tester.tap(find.text('Start Listening'));
    await settle(tester, frames: 2);
    expect(state.isListening, isTrue);
    expect(find.text('Stop Listening'), findsOneWidget);
    expect(audio.isCapturing, isTrue);

    // --- Type and send a message. ---
    const text = 'Hello from integration';
    final sendButton =
        find.widgetWithText(ElevatedButton, 'Send / Modulate & Play');
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Message'), text);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pump();

    // --- It goes out through the speaker and comes back decoded. ---
    final received = await waitFor(
        tester, () => state.messages.any((m) => m.contains(text)));
    expect(audio.playedSamples, greaterThan(0),
        reason: 'nothing was modulated and played');
    expect(received, isTrue,
        reason: 'not decoded; log so far: ${state.messages}');
    expect(state.messageRecords.first.text, text);
    expect(state.messageRecords.first.mode, 'OFDM');
    await settle(tester, frames: 2);
    expect(find.byKey(const Key('rx_live_region')), findsOneWidget);
    expect(find.textContaining('Last received: '), findsOneWidget);
    expect(find.textContaining(text), findsWidgets);
    // The field was cleared, so Send is disabled again once TX finishes.
    expect(await waitFor(tester, () => !state.isTransmitting), isTrue);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNull);

    // --- Other tabs of the main shell render. ---
    await tester.tap(find.text('Monitor'));
    await settle(tester);
    expect(find.text('Real-Time Signal Monitor'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('Settings & Configuration'), findsOneWidget);

    // --- Receiver off again. ---
    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.text('Stop Listening'));
    await settle(tester, frames: 2);
    expect(state.isListening, isFalse);

    // Settings changes made by the app went through the injected store.
    expect(store.values['modulation'], 1);
  });
}
