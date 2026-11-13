// End-to-end link-layer transfers (#89, #100) over the real native DSP: two
// in-process "devices" (TxEngine + RxEngine each) joined by a simulated
// acoustic channel with noise, local echo (each mic hears its own speaker)
// and a scripted frame loss. Skipped when libsoundwave cannot be loaded.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_frame.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/services/audio_service.dart';

/// Audio endpoint whose speaker output is routed by the test.
class BridgeAudio implements AudioService {
  final StreamController<Float64List> _mic =
      StreamController<Float64List>.broadcast();
  void Function(Float64List samples)? onPlay;
  Future<void> _micQueue = Future<void>.value();

  @override
  Stream<Float64List> get audioStream => _mic.stream;
  @override
  bool get isCapturing => true;
  @override
  bool get isPlaying => false;
  @override
  List<AudioDevice> get inputDevices => const [];
  @override
  List<AudioDevice> get outputDevices => const [];
  @override
  Future<void> startCapture() async {}
  @override
  Future<void> stopCapture() async {}
  @override
  Future<void> startPlayback() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  void updateConfig(Map<String, dynamic> config) {}

  @override
  Future<void> enqueueForPlayback(Float64List samples) async =>
      onPlay?.call(Float64List.fromList(samples));

  /// Queues [signal] (with noise around it) for this microphone. Deliveries
  /// are serialised so two transmissions never interleave mid-frame.
  void hear(Float64List signal, Random rnd, {required int trailing}) {
    _micQueue = _micQueue.then((_) async {
      const lead = 2000;
      final x = Float64List(lead + signal.length + trailing);
      for (var i = 0; i < x.length; i++) {
        x[i] = (rnd.nextDouble() * 2 - 1) * 0.01;
      }
      for (var i = 0; i < signal.length; i++) {
        x[lead + i] += signal[i];
      }
      for (var i = 0; i < x.length; i += 4096) {
        _mic.add(Float64List.sublistView(x, i, min(i + 4096, x.length)));
        await Future<void>.delayed(Duration.zero);
      }
    });
  }
}

class Device {
  final BridgeAudio audio = BridgeAudio();
  final Map<String, dynamic> config;
  late final TxEngine tx;
  late final RxEngine rx;
  final List<StreamSubscription<Object?>> _subs = [];

  Device(int nodeId, this.config, SoundwaveNative native) {
    tx = TxEngine(
        native: native,
        audio: audio,
        configMap: config,
        useIsolates: false,
        nodeId: nodeId,
        random: Random(nodeId));
    rx = RxEngine(
        native: native,
        audio: audio,
        configMap: config,
        useIsolates: false,
        nodeId: nodeId);
    // Same wiring as AppState._subscribeToLinkLayer.
    _subs.addAll([
      rx.controlFrames.listen(tx.onControlFrame),
      rx.controlReplies.listen((f) => tx.sendControl(f)),
    ]);
  }

  Future<void> dispose() async {
    rx.stopListening();
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

Map<String, dynamic> ofdmConfig({required bool arq}) => {
      'sample_rate': 44100,
      'modulation': 1,
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
      'arq_enabled': arq,
      'arq_max_retries': 5,
      'arq_ack_timeout_ms': 1000,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoundwaveNative? native;
  try {
    native = SoundwaveNative.instance;
  } catch (e) {
    // ignore: avoid_print
    print('Skipping link loopback tests: library not loadable ($e)');
  }
  final skip = native == null ? 'native library not available' : null;

  group('native link-layer end-to-end', () {
    late Device a, b;
    late Random rnd;
    late int trailing;

    /// Connects A and B; [dropAtoB] decides (per A transmission, 0-based)
    /// whether B misses it. Each mic also hears its own speaker.
    Future<void> connect(
        {required bool arq, bool Function(int n)? dropAtoB}) async {
      a = Device(0x0A0A, ofdmConfig(arq: arq), native!);
      b = Device(0x0B0B, ofdmConfig(arq: arq), native);
      rnd = Random(89100);
      final g = FrameGeometry.fromConfig(a.config);
      trailing = 2 * RxEngine.retryStepSymbols * g.samplesPerSymbol;
      var n = 0;
      a.audio.onPlay = (s) {
        a.audio.hear(s, rnd, trailing: trailing); // local echo
        if (!(dropAtoB?.call(n++) ?? false)) {
          b.audio.hear(s, rnd, trailing: trailing);
        }
      };
      b.audio.onPlay = (s) {
        b.audio.hear(s, rnd, trailing: trailing);
        a.audio.hear(s, rnd, trailing: trailing);
      };
      a.rx.startListening();
      b.rx.startListening();
      // Capture subscriptions are attached asynchronously; audio sent before
      // that would be lost.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    test('ARQ: multi-fragment file survives a lost fragment', () async {
      // A's 2nd transmission (fragment 1, first attempt) never reaches B.
      await connect(arq: true, dropAtoB: (n) => n == 1);
      final files = <ReceivedFile>[];
      final sub = b.rx.files.listen(files.add);
      final progress = <TxTransferProgress>[];
      final psub = a.tx.transfers.listen(progress.add);

      final data =
          Uint8List.fromList(List.generate(600, (i) => (i * 31) % 251));
      await a.tx
          .sendBinary(data, fileName: 'e2e.bin')
          .timeout(const Duration(seconds: 90));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      await psub.cancel();

      expect(files, hasLength(1)); // delivered exactly once
      expect(files.single.data, data);
      expect(files.single.fileName, 'e2e.bin');
      expect(files.single.src, 0x0A0A);
      expect(progress.last.state, TxTransferState.completed);
      expect(progress.last.fragmentCount, greaterThanOrEqualTo(3));
      expect(a.tx.retransmissions, greaterThanOrEqualTo(1));
      // B ACKed; A never ACKed its own echoes.
      expect(
          b.tx.framesSent, greaterThanOrEqualTo(progress.last.fragmentCount));
      expect(
          a.tx.framesSent, progress.last.fragmentCount + a.tx.retransmissions);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('broadcast (ARQ off): long text is fragmented and reassembled',
        () async {
      await connect(arq: false);
      final texts = <String>[];
      final sub = b.rx.messages.listen((m) => texts.add(m.text));
      final diag = <String>[];
      final dsubs = [
        b.rx.frameEvents.listen((e) {
          diag.add('B frame ${e.decoded} ${e.byteLength} ${e.errorMessage}');
        }),
        b.rx.transfers.listen((t) {
          diag.add('B rx ${t.received}/${t.count} ${t.state} ${t.error}');
        }),
        a.tx.transfers.listen((t) {
          diag.add('A tx ${t.fragmentsDone}/${t.fragmentCount} ${t.state}');
        }),
      ];
      final text =
          List.generate(450, (i) => String.fromCharCode(0x41 + i % 26)).join();
      await a.tx.sendMessage(text);
      // Fragments are paced by airtime; give the receiver time to drain.
      for (var i = 0; i < 100 && texts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await sub.cancel();
      for (final d in dsubs) {
        await d.cancel();
      }
      expect(texts, [text], reason: diag.join('; '));
      expect(a.tx.framesSent, greaterThan(1));
      expect(b.tx.framesSent, 0); // a pure listener never transmits
      expect(LinkFrame.maxChunk, lessThan(text.length));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: skip);
}
