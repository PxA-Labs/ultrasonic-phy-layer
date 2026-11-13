// RxEngine constellation stream (mock native; see test/native/ for the
// real equalizer output).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/dsp/constellation.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/rx_engine.dart';

import 'mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSoundwaveNative native;
  late MockAudioService audio;
  late Map<String, dynamic> config;

  setUp(() {
    native = MockSoundwaveNative()..framesToDetect = 1;
    audio = MockAudioService();
    config = {'modulation': 1, 'sample_rate': 44100, 'ofdm_modulation': 1};
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  int samplesFor(int frameBytes) {
    final g = FrameGeometry.fromConfig(config);
    return g.searchWindowSamples + g.samplesForFrameBytes(frameBytes);
  }

  RxEngine build() => RxEngine(
        native: native,
        audio: audio,
        configMap: config,
        useIsolates: false,
      );

  test('emits the equalized points of a decoded OFDM frame', () async {
    final rx = build();
    final frames = <ConstellationFrame>[];
    final sub = rx.constellation.listen(frames.add);
    rx.startListening();
    await settle();
    audio.pushMockChunk(Float64List(samplesFor(39)));
    await settle();
    rx.stopListening();
    await sub.cancel();

    expect(rx.framesReceived, 1);
    expect(native.equalizedSymbolCalls, 1);
    expect(frames, hasLength(1));
    expect(frames.single.decoded, isTrue);
    expect(frames.single.scheme, ConstellationScheme.qpsk);
    expect(frames.single.pointCount, 4);
    expect(frames.single.evm!.rms, closeTo(0, 1e-6));
  });

  test('BPSK setting selects the BPSK reference grid', () async {
    config['ofdm_modulation'] = 0;
    native.equalizedSymbols = Float32List.fromList([1, 0, -1, 0]);
    final rx = build();
    final frames = <ConstellationFrame>[];
    final sub = rx.constellation.listen(frames.add);
    rx.startListening();
    await settle();
    audio.pushMockChunk(Float64List(samplesFor(39)));
    await settle();
    rx.stopListening();
    await sub.cancel();
    expect(frames.single.scheme, ConstellationScheme.bpsk);
  });

  test('costs nothing without a listener or on old libraries', () async {
    // No listener.
    var rx = build();
    rx.startListening();
    await settle();
    audio.pushMockChunk(Float64List(samplesFor(39)));
    await settle();
    rx.stopListening();
    expect(rx.framesReceived, 1);
    expect(native.equalizedSymbolCalls, 0);

    // Library without sw_ofdm_equalized_symbols.
    native = MockSoundwaveNative()
      ..framesToDetect = 1
      ..hasEqualizedSymbols = false;
    rx = build();
    final frames = <ConstellationFrame>[];
    final sub = rx.constellation.listen(frames.add);
    rx.startListening();
    await settle();
    audio.pushMockChunk(Float64List(samplesFor(39)));
    await settle();
    rx.stopListening();
    await sub.cancel();
    expect(rx.framesReceived, 1);
    expect(native.equalizedSymbolCalls, 0);
    expect(frames, isEmpty);
  });
}
