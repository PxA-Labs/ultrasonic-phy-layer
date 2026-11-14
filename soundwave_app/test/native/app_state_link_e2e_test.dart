// AppState-level link layer over the real native DSP (#89, #100, #34): two
// app instances joined by a simulated acoustic channel. Covers what the
// engine-level link tests do not: AppState's wiring of control frames,
// replies, file saving (success and failure), transfer progress, the message
// log and the live metrics. Skipped when libsoundwave cannot be loaded.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_receiver.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/services/received_file_store.dart';
import 'package:soundwave/state/app_state.dart';

import 'link_loopback_test.dart' show BridgeAudio;

/// Keeps saved files in memory, or fails every save when [failWith] is set.
class MemoryFileSink implements ReceivedFileSink {
  final Map<String, Uint8List> files = {};
  final Object? failWith;
  MemoryFileSink({this.failWith});

  @override
  Future<String> save(String fileName, Uint8List data) async {
    if (failWith != null) throw failWith!;
    files[fileName] = data;
    return 'mem://$fileName';
  }
}

class Peer {
  final BridgeAudio audio = BridgeAudio();
  final MemoryFileSink sink;
  late final AppState state;

  Peer({required bool arq, MemoryFileSink? sink})
      : sink = sink ?? MemoryFileSink() {
    state = AppState(audio: audio, fileSink: this.sink);
    state.setMode(1); // OFDM
    state.setArqEnabled(arq);
    state.setArqMaxRetries(5);
    state.setArqAckTimeoutMs(1000);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping AppState link tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  group('AppState link layer end-to-end', () {
    late Peer a, b;
    final rnd = Random(3436);

    /// Wires A <-> B (each mic also hears its own speaker) and starts B
    /// listening with half a second of background noise for AGC to settle.
    Future<void> connect({required bool arq, MemoryFileSink? bSink}) async {
      a = Peer(arq: arq);
      b = Peer(arq: arq, sink: bSink);
      final g = FrameGeometry.fromConfig(a.state.configMap);
      final trailing = 2 * RxEngine.retryStepSymbols * g.samplesPerSymbol;
      a.audio.onPlay = (s) {
        a.audio.hear(s, rnd, trailing: trailing);
        b.audio.hear(s, rnd, trailing: trailing);
      };
      b.audio.onPlay = (s) {
        b.audio.hear(s, rnd, trailing: trailing);
        a.audio.hear(s, rnd, trailing: trailing);
      };
      b.state.toggleListening();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.audio.hear(Float64List(0), rnd, trailing: 22050);
      a.audio.hear(Float64List(0), rnd, trailing: 22050);
    }

    Future<void> waitUntil(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    tearDown(() {
      a.state.dispose();
      b.state.dispose();
    });

    test('ARQ file transfer: saved, logged, progress and metrics updated',
        () async {
      await connect(arq: true);
      final data =
          Uint8List.fromList(List.generate(600, (i) => (i * 17 + 3) % 256));
      expect(a.state.isListening, isFalse);

      await a.state
          .sendFileBytes(data, fileName: 'report.bin')
          .timeout(const Duration(seconds: 90));

      // ARQ needs to hear ACKs, so sending switched A's receiver on.
      expect(a.state.isListening, isTrue);
      expect(a.state.transferError, isNull);
      expect(a.state.txTransfer?.state, TxTransferState.completed);
      expect(a.state.txTransfer!.fragmentCount, greaterThanOrEqualTo(3));
      expect(a.state.isTransmitting, isFalse);

      await waitUntil(() => b.state.receivedFiles.isNotEmpty);
      expect(b.state.receivedFiles, hasLength(1));
      final rec = b.state.receivedFiles.single;
      expect(rec.fileName, 'report.bin');
      expect(rec.size, 600);
      expect(rec.savedPath, 'mem://report.bin');
      expect(rec.error, isNull);
      expect(b.sink.files['report.bin'], data);
      expect(b.state.messages.first, contains('File "report.bin" (600 B)'));
      expect(b.state.rxTransfer?.state, RxTransferState.completed);

      // A must not have "received" its own echo.
      expect(a.state.receivedFiles, isEmpty);

      // Live metrics on both sides.
      expect(a.state.metrics.totalBytesTransferred, greaterThan(0));
      expect(b.state.metrics.framesReceived, greaterThanOrEqualTo(3));
      expect(b.state.metrics.totalBytesTransferred, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a failing file store is reported, not swallowed', () async {
      await connect(arq: false, bSink: MemoryFileSink(failWith: 'disk full'));
      final data = Uint8List.fromList(List.generate(40, (i) => i));
      await a.state.sendFileBytes(data, fileName: 'x.txt');
      expect(a.state.txTransfer?.state, TxTransferState.completed);

      await waitUntil(() => b.state.receivedFiles.isNotEmpty);
      final rec = b.state.receivedFiles.single;
      expect(rec.savedPath, isNull);
      expect(rec.error, contains('disk full'));
      expect(rec.mimeType, 'text/plain');
      expect(b.state.messages.first, contains('File "x.txt" (40 B)'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: skip);
}
