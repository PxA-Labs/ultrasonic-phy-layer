// Real-DSP round trip through files (#33): modulate -> WAV on disk (written by
// WavRecorder or encodeWav) -> SignalImporter -> OfflineDecoder (RxEngine).
//
// Runs only when libsoundwave can be loaded; CI sets SOUNDWAVE_LIB and
// SOUNDWAVE_REQUIRE_NATIVE (see loopback_test.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/export/offline_decoder.dart';
import 'package:soundwave/export/signal_importer.dart';
import 'package:soundwave/export/wav_format.dart';
import 'package:soundwave/export/wav_recorder.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

Map<String, dynamic> config({required int modulation}) => {
      'sample_rate': 44100,
      'modulation': modulation,
      'sf': 8,
      'num_subcarriers': 256,
      'cp_length': 64,
      'num_pilots': 8,
      'carrier_freq': 19000.0,
      'bandwidth': 2000.0,
      'symbol_duration': 0.02,
      'amplitude': 0.8,
      'ofdm_modulation': 1,
      'threshold': 3.0,
      'equalizer': 0,
      'coding_rate': 0.5,
      'enable_rs': true,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping WAV loopback tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sw_wavloop_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Modulated frames for [texts], each with noise around it, as one signal.
  Float64List transmission(Map<String, dynamic> cfg, List<String> texts) {
    final nat = native!;
    final codec = FrameCodec(nat);
    final rnd = Random(33);
    final out = <double>[];
    void noise(int n) {
      for (var i = 0; i < n; i++) {
        out.add((rnd.nextDouble() * 2 - 1) * 0.01);
      }
    }

    for (final t in texts) {
      final frame = codec.encode(Uint8List.fromList(utf8.encode(t)));
      final p = SwConfig.fromMap(cfg);
      final Float32List s;
      try {
        if (cfg['modulation'] == 1) {
          s = nat.ofdmModulate(frame, p);
        } else {
          s = nat.cssModulate(frame, p);
        }
      } finally {
        calloc.free(p);
      }
      noise(3000);
      for (final v in s) {
        out.add(v + (rnd.nextDouble() * 2 - 1) * 0.01);
      }
      noise(1500);
    }
    return Float64List.fromList(out);
  }

  Future<List<String>> decodeFile(
    String path,
    Map<String, dynamic> cfg,
  ) async {
    final signal = await const SignalImporter().importFile(path);
    final got = await OfflineDecoder.decode(
      signal.samples,
      cfg,
      signal.sampleRate,
      native: native,
    );
    return got.map((m) => m.text).toList();
  }

  group('WAV file loopback (real DSP)', () {
    test('OFDM: WavRecorder file decodes both messages', () async {
      final cfg = config(modulation: 1);
      final x = transmission(cfg, ['from a recording', 'second frame']);
      final rec = WavRecorder();
      final path = await rec.startRecording(dir);
      // Stream it in capture-sized chunks, as the app does.
      for (var i = 0; i < x.length; i += 441) {
        rec.addSamples(Float64List.sublistView(x, i, min(i + 441, x.length)));
      }
      await rec.stopRecording();

      final parsed = parseWav(File(path).readAsBytesSync());
      expect(parsed.samples.length, x.length);
      expect(await decodeFile(path, cfg), ['from a recording', 'second frame']);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('CSS: 16-bit WAV file decodes', () async {
      final cfg = config(modulation: 0);
      final path = '${dir.path}${Platform.pathSeparator}css.wav';
      File(path).writeAsBytesSync(encodeWav(transmission(cfg, ['Hi'])));
      expect(await decodeFile(path, cfg), ['Hi']);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('OFDM: float32 WAV file decodes', () async {
      final cfg = config(modulation: 1);
      final path = '${dir.path}${Platform.pathSeparator}f32.wav';
      final x = transmission(cfg, ['float wav']);
      final wav = encodeWav(x, format: WavSampleFormat.float32);
      File(path).writeAsBytesSync(wav);
      expect(await decodeFile(path, cfg), ['float wav']);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('noise-only file decodes nothing', () async {
      final cfg = config(modulation: 1);
      final rnd = Random(1);
      final x = Float64List(44100);
      for (var i = 0; i < x.length; i++) {
        x[i] = (rnd.nextDouble() * 2 - 1) * 0.01;
      }
      final path = '${dir.path}${Platform.pathSeparator}noise.wav';
      File(path).writeAsBytesSync(encodeWav(x));
      expect(await decodeFile(path, cfg), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: skip);
}
