// Cross-compatibility between the app and soundwave-cli: both must use the
// same PHY frame ([CRC-32 LE][payload][RS parity], no length field; see
// docs/DEVELOPER_GUIDE.md "PHY frame format") and the same modem defaults,
// so a WAV written by one decodes in the other.
//
//   app -> CLI: FrameCodec + sw_*_modulate (real DSP via FFI) -> 16-bit WAV
//               -> `soundwave-cli demodulate`
//   CLI -> app: `soundwave-cli modulate` -> WAV -> SignalImporter ->
//               OfflineDecoder (the app's RxEngine)
//
// Needs libsoundwave (SOUNDWAVE_LIB) and the CLI binary (SOUNDWAVE_CLI). CI
// builds both and sets SOUNDWAVE_REQUIRE_CLI=1 so a missing binary fails
// instead of skipping.

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
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/native/soundwave_native.dart';

/// The app's defaults, which are also soundwave-cli's defaults.
Map<String, dynamic> appConfig({required int modulation}) => {
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
    print('Skipping CLI compatibility tests: library not loadable ($e)');
  }
  final cli = Platform.environment['SOUNDWAVE_CLI'];
  final haveCli = cli != null && File(cli).existsSync();
  final skip = native == null
      ? 'native library not available'
      : (haveCli ? null : 'SOUNDWAVE_CLI not set');

  test('soundwave-cli is available when required', () {
    if (Platform.environment['SOUNDWAVE_REQUIRE_CLI'] == '1') {
      expect(haveCli, isTrue, reason: 'set SOUNDWAVE_CLI to a built binary');
      expect(native, isNotNull);
    }
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sw_cli_compat_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String mode(Map<String, dynamic> cfg) =>
      cfg['modulation'] == 1 ? 'ofdm' : 'css';

  group('frame format', () {
    test('app frame bytes match the CLI golden layout', () {
      // Same vector as native/tests/test_cli_frame.c.
      final bytes = utf8.encode('hello');
      const golden = [0x86, 0xA6, 0x10, 0x36, 0x68, 0x65, 0x6C, 0x6C, 0x6F];
      final f = FrameCodec(native!).encode(bytes);
      expect(f.length, 4 + 5 + 32);
      expect(f.sublist(0, 9), golden);
      final plain = FrameCodec(native).encode(bytes, enableRs: false);
      expect(plain, golden);
    });
  }, skip: native == null ? 'native library not available' : null);

  group('app -> soundwave-cli', () {
    for (final modulation in [1, 0]) {
      final cfg = appConfig(modulation: modulation);
      test('${mode(cfg)}: app WAV decodes in the CLI', () async {
        const text = 'from the app 42';
        final frame = FrameCodec(native!).encode(utf8.encode(text));
        final p = SwConfig.fromMap(cfg);
        final Float32List s;
        try {
          s = modulation == 1
              ? native.ofdmModulate(frame, p)
              : native.cssModulate(frame, p);
        } finally {
          calloc.free(p);
        }
        // Lead-in and trailing noise, as a recording would have.
        final rnd = Random(7);
        final x = <double>[
          for (var i = 0; i < 2000; i++) (rnd.nextDouble() * 2 - 1) * 0.005,
          for (final v in s) v + (rnd.nextDouble() * 2 - 1) * 0.005,
          for (var i = 0; i < 1000; i++) (rnd.nextDouble() * 2 - 1) * 0.005,
        ];
        final path = '${dir.path}${Platform.pathSeparator}app.wav';
        File(path).writeAsBytesSync(encodeWav(x));
        final args = ['demodulate', '--mode', mode(cfg), '--input', path];
        final res = await Process.run(cli!, args);
        expect(res.exitCode, 0, reason: '${res.stderr}');
        expect(res.stdout, '$text\n');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  }, skip: skip);

  group('soundwave-cli -> app', () {
    test('ofdm: CLI WAV decodes in the app RxEngine', () async {
      final cfg = appConfig(modulation: 1);
      const text = 'from the CLI 7';
      final path = '${dir.path}${Platform.pathSeparator}cli.wav';
      final args = ['modulate', '--mode', 'ofdm', '--input', text, '--output'];
      final res = await Process.run(cli!, [...args, path]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      final signal = await const SignalImporter().importFile(path);
      final got = await OfflineDecoder.decode(
        signal.samples,
        cfg,
        signal.sampleRate,
        native: native,
      );
      expect(got.map((m) => m.text).toList(), [text]);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: skip);
}
