// OfflineDecoder against the mock native layer (the real-DSP version lives in
// test/native/wav_loopback_test.dart).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/export/offline_decoder.dart';

import '../engine/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final config = <String, dynamic>{'modulation': 1, 'sample_rate': 44100};

  int samplesFor(int frameBytes) {
    final g = FrameGeometry.fromConfig(config);
    return g.searchWindowSamples + g.samplesForFrameBytes(frameBytes);
  }

  test('streams a buffer through RxEngine and returns decoded frames',
      () async {
    final native = MockSoundwaveNative()..framesToDetect = 1;
    final got = await OfflineDecoder.decode(
      Float64List(samplesFor(39)),
      config,
      44100,
      native: native,
    );
    expect(got, hasLength(1));
    expect(got.single.text, '\x01\x02\x03');
    expect(got.single.rawBytes, [1, 2, 3]);
  });

  test('returns nothing when no frame is detected', () async {
    final native = MockSoundwaveNative()..framesToDetect = 0;
    final got = await OfflineDecoder.decode(
      Float64List(samplesFor(39)),
      config,
      44100,
      native: native,
    );
    expect(got, isEmpty);
    expect(native.demodCalls, 0);
  });

  test('does not modify the caller config', () async {
    final cfg = Map<String, dynamic>.from(config);
    final native = MockSoundwaveNative()..framesToDetect = 0;
    await OfflineDecoder.decode(Float64List(10), cfg, 8000, native: native);
    expect(cfg['sample_rate'], 44100);
  });

  test('rejects a non-positive sample rate', () async {
    await expectLater(
      OfflineDecoder.decode(Float64List(10), config, 0),
      throwsArgumentError,
    );
  });
}
