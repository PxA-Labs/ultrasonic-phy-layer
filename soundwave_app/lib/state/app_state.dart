// App state — ChangeNotifier-based reactive state for the whole application.
// Holds modem config, TX/RX status, real-time signal metrics, and received messages.
// Follows OpenSSF secure coding guidelines with robust bounds checks and lifecycle cleanup.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:soundwave/dsp/constellation.dart';
import 'package:soundwave/engine/arq.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/link_receiver.dart';
import 'package:soundwave/services/received_file_store.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/tx_queue.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'package:soundwave/engine/throughput_calculator.dart';
import 'package:soundwave/engine/transfer_notice.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/state/settings_store.dart';
import 'package:soundwave/export/message_exporter.dart';
import 'package:soundwave/export/offline_decoder.dart';
import 'package:soundwave/export/signal_importer.dart';
import 'package:soundwave/export/signal_sample_store.dart';
import 'package:soundwave/export/soundwave_storage.dart';
import 'package:soundwave/export/wav_recorder.dart';

class AppState extends ChangeNotifier {
  // Config fields
  int _sampleRate = 44100;
  int _mode = 0; // 0=CSS, 1=OFDM
  int _sf = 8;
  int _numSubcarriers = 256;
  int _cpLength = 64;
  int _numPilots = 8;
  double _carrierFreq = 19000.0;
  double _bandwidth = 2000.0;
  double _amplitude = 0.8;
  int _ofdmModulation = 1; // QPSK
  double _threshold = 3.0;
  int _equalizer = 0; // 0 = ZF, 1 = MMSE
  bool _enableRs = true;
  double _volume = 0.8;
  bool _agcEnabled = true; // RX automatic gain control (#92)
  // Link-layer ARQ (#100). Off by default so one-way broadcast just works.
  bool _arqEnabled = false;
  int _arqMaxRetries = 3;
  int _arqAckTimeoutMs = 500;

  // Audio devices
  AudioDevice? _inputDevice;
  AudioDevice? _outputDevice;

  // Active state
  bool _isListening = false;
  double _lastSnr = 0.0;
  String _txMessage = '';
  final List<String> _messages = [];
  bool _isTransmitting = false;

  late final AudioService _audio;
  late final TxEngine _txEngine;
  late final RxEngine _rxEngine;
  late final TxQueue _txQueue;
  late final ThroughputCalculator _throughputCalculator;
  late SignalMetrics _metrics;

  StreamSubscription<DecodedMessage>? _rxSubscription;
  StreamSubscription<RxFrameEvent>? _rxFrameEventsSubscription;
  StreamSubscription<TxMetrics>? _txMetricsSubscription;
  final List<StreamSubscription<Object?>> _linkSubscriptions = [];

  // File transfer (#89)
  late final int nodeId;
  final ReceivedFileSink _fileSink;
  TxTransferProgress? _txTransfer;
  RxTransferProgress? _rxTransfer;
  String? _transferError;
  final List<ReceivedFileRecord> _receivedFiles = [];
  final StreamController<TransferNotice> _transferNotices =
      StreamController<TransferNotice>.broadcast();

  /// One event per finished file transfer, sent or received (#89).
  Stream<TransferNotice> get transferNotices => _transferNotices.stream;
  TransferNotice? _lastTransferNotice;
  TransferNotice? get lastTransferNotice => _lastTransferNotice;

  void _notifyTransfer(TransferNotice n) {
    _lastTransferNotice = n;
    if (!_transferNotices.isClosed) _transferNotices.add(n);
  }

  Timer? _throughputTimer;
  bool _isDisposed = false;

  final SettingsStore? _store;

  late final Map<String, dynamic> _configMap;
  Map<String, dynamic> get configMap => _configMap;

  void _syncConfigMap() {
    _configMap['sample_rate'] = _sampleRate;
    _configMap['modulation'] = _mode;
    _configMap['sf'] = _sf;
    _configMap['num_subcarriers'] = _numSubcarriers;
    _configMap['cp_length'] = _cpLength;
    _configMap['num_pilots'] = _numPilots;
    _configMap['carrier_freq'] = _carrierFreq;
    _configMap['bandwidth'] = _bandwidth;
    _configMap['amplitude'] = _amplitude;
    _configMap['ofdm_modulation'] = _ofdmModulation;
    _configMap['threshold'] = _threshold;
    _configMap['equalizer'] = _equalizer;
    _configMap['enable_rs'] = _enableRs;
    _configMap['volume'] = _volume;
    _configMap['agc_enabled'] = _agcEnabled;
    _configMap['arq_enabled'] = _arqEnabled;
    _configMap['arq_max_retries'] = _arqMaxRetries;
    _configMap['arq_ack_timeout_ms'] = _arqAckTimeoutMs;
  }

  AppState({
    AudioService? audio,
    SettingsStore? store,
    ReceivedFileSink? fileSink,
  })  : _store = store,
        _fileSink = fileSink ?? DirectoryFileSink() {
    _configMap = {};
    _syncConfigMap();
    _audio = audio ?? AudioService.preferred(_configMap);
    nodeId = TxEngine.randomNodeId();
    _txEngine = TxEngine(
        audio: _audio,
        configMap: _configMap,
        useIsolates: false,
        nodeId: nodeId);
    _rxEngine = RxEngine(
        audio: _audio,
        configMap: _configMap,
        useIsolates: false,
        nodeId: nodeId);
    _txQueue = TxQueue(txEngine: _txEngine);
    _throughputCalculator =
        ThroughputCalculator(windowDuration: const Duration(seconds: 5));
    _metrics = SignalMetrics(lastUpdated: DateTime.now());

    // Prepopulate audio devices
    if (_audio.inputDevices.isNotEmpty) {
      _inputDevice = _audio.inputDevices.first;
    }
    if (_audio.outputDevices.isNotEmpty) {
      _outputDevice = _audio.outputDevices.first;
    }

    _subscribeToEngineMetrics();
    _captureTap = _audio.audioStream.listen(_onCapturedAudio);
    _subscribeToLinkLayer();
  }

  /// Wires the link layer: ACK/NACKs heard by RX go to the TX ARQ sender,
  /// replies requested by RX are transmitted, received files are saved.
  void _subscribeToLinkLayer() {
    _linkSubscriptions.addAll([
      _rxEngine.controlFrames.listen(_txEngine.onControlFrame),
      _rxEngine.controlReplies.listen((frame) {
        _txEngine.sendControl(frame).catchError((Object e) {
          debugPrint('Failed to send $frame: $e');
        });
      }),
      _rxEngine.files.listen(_onFileReceived),
      _rxEngine.transfers.listen((p) {
        _rxTransfer = p;
        notifyListeners();
      }),
      _txEngine.transfers.listen((p) {
        _txTransfer = p;
        _onTxTransferProgress(p);
        notifyListeners();
      }),
    ]);
  }

  /// File transfers that ended (not text, not a user cancel) get a notice.
  void _onTxTransferProgress(TxTransferProgress p) {
    final name = p.fileName;
    if (name == null) return;
    if (p.state != TxTransferState.completed &&
        p.state != TxTransferState.failed) {
      return;
    }
    _notifyTransfer(TransferNotice(
      direction: TransferDirection.sent,
      fileName: name,
      bytes: p.contentBytes,
      duration: p.elapsed,
      ok: p.state == TxTransferState.completed,
      error: p.error,
      retransmissions: p.retransmissions,
    ));
  }

  Future<void> _onFileReceived(ReceivedFile file) async {
    String? path;
    String? error;
    try {
      path = await _fileSink.save(file.fileName, file.data);
    } catch (e) {
      error = '$e';
      debugPrint('Failed to save received file: $e');
    }
    if (_isDisposed) return;
    _receivedFiles.insert(
      0,
      ReceivedFileRecord(
        fileName: file.fileName,
        mimeType: file.mimeType,
        size: file.data.length,
        timestamp: file.timestamp,
        savedPath: path,
        error: error,
        transferTime: file.transferTime,
      ),
    );
    if (_receivedFiles.length > 50) _receivedFiles.removeLast();
    _notifyTransfer(TransferNotice(
      direction: TransferDirection.received,
      fileName: file.fileName,
      bytes: file.data.length,
      duration: file.transferTime,
      ok: path != null,
      error: error,
    ));
    addMessage('File "${file.fileName}" (${file.data.length} B)', file.snr);
  }

  void _subscribeToEngineMetrics() {
    _txMetricsSubscription = _txEngine.metrics.listen((tx) {
      _throughputCalculator.recordTransfer(tx.bytesSent, tx.timestamp);
      _metrics = _metrics.copyWith(
        bitsPerSecond: _throughputCalculator.calculateBitsPerSecond(),
        totalBytesTransferred: _metrics.totalBytesTransferred + tx.bytesSent,
        lastUpdated: tx.timestamp,
      );
      _startThroughputTimer();
      notifyListeners();
    });

    _rxFrameEventsSubscription = _rxEngine.frameEvents.listen((event) {
      if (event.decoded && event.byteLength > 0) {
        _throughputCalculator.recordTransfer(event.byteLength, event.timestamp);
        _startThroughputTimer();
      }
      _lastSnr = event.snr;

      ModemLinkState nextState;
      if (_isTransmitting) {
        nextState = ModemLinkState.transmitting;
      } else if (event.decoded) {
        nextState =
            _isListening ? ModemLinkState.listening : ModemLinkState.idle;
      } else if (event.errorMessage != null) {
        nextState = ModemLinkState.error;
      } else {
        nextState = ModemLinkState.receiving;
      }

      _metrics = _metrics.copyWith(
        connectionState: nextState,
        snr: event.snr,
        bitsPerSecond: _throughputCalculator.calculateBitsPerSecond(),
        totalBytesTransferred:
            _metrics.totalBytesTransferred + event.byteLength,
        framesReceived: _rxEngine.framesReceived,
        framesDetected: _rxEngine.framesDetected,
        frameErrors: _rxEngine.frameErrors,
        lastUpdated: event.timestamp,
      );
      notifyListeners();
    });
  }

  void _startThroughputTimer() {
    if (_isDisposed || _throughputTimer != null) return;
    _throughputTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isDisposed) {
        _stopThroughputTimer();
        return;
      }
      final currentBps = _throughputCalculator.calculateBitsPerSecond();
      final agc = _rxEngine.agcGainDb;
      final prevAgc = _metrics.agcGainDb;
      final agcChanged = (agc == null) != (prevAgc == null) ||
          (agc != null && prevAgc != null && (agc - prevAgc).abs() >= 0.5);
      if ((currentBps - _metrics.bitsPerSecond).abs() > 0.01 || agcChanged) {
        _metrics = _metrics.copyWith(
          bitsPerSecond: currentBps,
          agcGainDb: agc,
          clearAgcGain: agc == null,
          lastUpdated: DateTime.now(),
        );
        notifyListeners();
      }
      if (!_isListening && !_isTransmitting && currentBps <= 0.0) {
        _stopThroughputTimer();
      }
    });
  }

  void _stopThroughputTimer() {
    _throughputTimer?.cancel();
    _throughputTimer = null;
  }

  // Getters
  SignalMetrics get metrics => _metrics;
  ModemLinkState get connectionState => _metrics.connectionState;

  int get sampleRate => _sampleRate;
  int get mode => _mode;
  int get sf => _sf;
  int get numSubcarriers => _numSubcarriers;
  int get cpLength => _cpLength;
  int get numPilots => _numPilots;
  double get carrierFreq => _carrierFreq;
  double get bandwidth => _bandwidth;

  /// CSS waveform derived from the current SF / bandwidth / sample rate:
  /// symbol duration 2^SF / B and SF bits per chirp (computed, not a knob).
  FrameGeometry get cssGeometry =>
      FrameGeometry.fromConfig({..._configMap, 'modulation': 0});

  /// Duration of one CSS chirp symbol in seconds (computed from SF and B).
  double get symbolDuration => cssGeometry.symbolSeconds;
  double get amplitude => _amplitude;
  int get ofdmModulation => _ofdmModulation;
  double get threshold => _threshold;
  int get equalizer => _equalizer;
  bool get enableRs => _enableRs;
  double get volume => _volume;
  bool get agcEnabled => _agcEnabled;
  bool get arqEnabled => _arqEnabled;
  int get arqMaxRetries => _arqMaxRetries;
  int get arqAckTimeoutMs => _arqAckTimeoutMs;

  /// Latest outgoing / incoming fragmented transfer, for progress display.
  TxTransferProgress? get txTransfer => _txTransfer;
  RxTransferProgress? get rxTransfer => _rxTransfer;

  /// Error of the last failed outgoing file transfer, if any.
  String? get transferError => _transferError;
  List<ReceivedFileRecord> get receivedFiles =>
      List.unmodifiable(_receivedFiles);

  AudioDevice? get inputDevice => _inputDevice;
  AudioDevice? get outputDevice => _outputDevice;
  List<AudioDevice> get inputDevices => _audio.inputDevices;
  List<AudioDevice> get outputDevices => _audio.outputDevices;

  bool get isListening => _isListening;
  double get lastSnr => _lastSnr;
  String get txMessage => _txMessage;
  List<String> get messages => List.unmodifiable(_messages);
  bool get isTransmitting => _isTransmitting;

  void _updateConfigField(String key, dynamic value) {
    _configMap[key] = value;
    _audio.updateConfig(_configMap);
    _persist();
    notifyListeners();
  }

  /// Saves the modem configuration (no-op without a store).
  void _persist() {
    final store = _store;
    if (store == null || _isDisposed) return;
    final snapshot = <String, Object>{
      for (final e in _configMap.entries)
        if (e.value is Object) e.key: e.value as Object,
    };
    store.save(snapshot).catchError((Object e) {
      debugPrint('Failed to persist settings: $e');
    });
  }

  /// Loads persisted settings, keeping only well-typed in-range values.
  Future<void> restoreSettings() async {
    final store = _store;
    if (store == null) return;
    final Map<String, Object> raw;
    try {
      raw = await store.load();
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      return;
    }
    if (_isDisposed) return;
    final v = ModemSettingsSchema.sanitize(raw);
    _sampleRate = v['sample_rate'] as int? ?? _sampleRate;
    _mode = v['modulation'] as int? ?? _mode;
    _sf = v['sf'] as int? ?? _sf;
    _numSubcarriers = v['num_subcarriers'] as int? ?? _numSubcarriers;
    _cpLength = v['cp_length'] as int? ?? _cpLength;
    _numPilots = v['num_pilots'] as int? ?? _numPilots;
    _carrierFreq = v['carrier_freq'] as double? ?? _carrierFreq;
    _bandwidth = v['bandwidth'] as double? ?? _bandwidth;
    _amplitude = v['amplitude'] as double? ?? _amplitude;
    _ofdmModulation = v['ofdm_modulation'] as int? ?? _ofdmModulation;
    _threshold = v['threshold'] as double? ?? _threshold;
    _equalizer = v['equalizer'] as int? ?? _equalizer;
    _enableRs = v['enable_rs'] as bool? ?? _enableRs;
    _volume = v['volume'] as double? ?? _volume;
    _agcEnabled = v['agc_enabled'] as bool? ?? _agcEnabled;
    _arqEnabled = v['arq_enabled'] as bool? ?? _arqEnabled;
    _arqMaxRetries = v['arq_max_retries'] as int? ?? _arqMaxRetries;
    _arqAckTimeoutMs = v['arq_ack_timeout_ms'] as int? ?? _arqAckTimeoutMs;
    // A cp from a different FFT size must still be a valid option.
    if (!cpOptionsFor(_numSubcarriers).contains(_cpLength)) {
      _cpLength = _numSubcarriers ~/ 8;
    }
    _syncConfigMap();
    _audio.updateConfig(_configMap);
    notifyListeners();
  }

  /// Cyclic-prefix choices offered for an FFT size: N/4, N/8, N/16.
  static List<int> cpOptionsFor(int n) => [n ~/ 4, n ~/ 8, n ~/ 16];

  // Setters
  set txMessage(String v) {
    _txMessage = v;
    notifyListeners();
  }

  void setMode(int m) {
    _mode = m;
    _updateConfigField('modulation', m);
  }

  void setSf(int v) {
    _sf = v;
    _updateConfigField('sf', v);
  }

  void setNumSubcarriers(int v) {
    // Keep the same CP fraction (N/4, N/8 or N/16) so the CP stays a valid
    // option for the new FFT size.
    final ratio = _numSubcarriers > 0 ? _cpLength / _numSubcarriers : 0.125;
    final options = cpOptionsFor(v);
    var best = options[1];
    for (final o in options) {
      if ((o / v - ratio).abs() < (best / v - ratio).abs()) best = o;
    }
    _numSubcarriers = v;
    _cpLength = best;
    _configMap['cp_length'] = best;
    _updateConfigField('num_subcarriers', v);
  }

  void setCpLength(int v) {
    _cpLength = v;
    _updateConfigField('cp_length', v);
  }

  void setNumPilots(int v) {
    _numPilots = v;
    _updateConfigField('num_pilots', v);
  }

  void setCarrierFreq(double v) {
    _carrierFreq = v;
    _updateConfigField('carrier_freq', v);
  }

  void setBandwidth(double v) {
    _bandwidth = v;
    _updateConfigField('bandwidth', v);
  }

  void setAmplitude(double v) {
    _amplitude = v;
    _updateConfigField('amplitude', v);
  }

  void setOfdmModulation(int v) {
    _ofdmModulation = v;
    _updateConfigField('ofdm_modulation', v);
  }

  void setThreshold(double v) {
    _threshold = v;
    _updateConfigField('threshold', v);
  }

  void setEqualizer(int v) {
    _equalizer = v;
    _updateConfigField('equalizer', v);
  }

  void setEnableRs(bool v) {
    _enableRs = v;
    _updateConfigField('enable_rs', v);
  }

  void setVolume(double v) {
    _volume = v;
    _updateConfigField('volume', v);
  }

  void setAgcEnabled(bool v) {
    _agcEnabled = v;
    if (!v) _metrics = _metrics.copyWith(clearAgcGain: true);
    _updateConfigField('agc_enabled', v);
  }

  void setArqEnabled(bool v) {
    _arqEnabled = v;
    _updateConfigField('arq_enabled', v);
  }

  void setArqMaxRetries(int v) {
    _arqMaxRetries = v;
    _updateConfigField('arq_max_retries', v);
  }

  void setArqAckTimeoutMs(int v) {
    _arqAckTimeoutMs = v < ArqConfig.minAckTimeoutMs
        ? ArqConfig.minAckTimeoutMs
        : (v > ArqConfig.maxAckTimeoutMs ? ArqConfig.maxAckTimeoutMs : v);
    _updateConfigField('arq_ack_timeout_ms', _arqAckTimeoutMs);
  }

  void setInputDevice(AudioDevice? device) {
    _inputDevice = device;
    notifyListeners();
  }

  void setOutputDevice(AudioDevice? device) {
    _outputDevice = device;
    notifyListeners();
  }

  void toggleListening() {
    if (_isListening) {
      _rxSubscription?.cancel();
      _rxSubscription = null;
      _rxEngine.stopListening();
      _isListening = false;
      _finishRecordingQuietly(); // capture stops with listening
      _metrics = _metrics.copyWith(
        clearAgcGain: true,
        connectionState:
            _isTransmitting ? ModemLinkState.transmitting : ModemLinkState.idle,
      );
      if (!_isTransmitting) {
        _stopThroughputTimer();
      }
    } else {
      _isListening = true;
      _metrics = _metrics.copyWith(
        connectionState: _isTransmitting
            ? ModemLinkState.transmitting
            : ModemLinkState.listening,
      );
      _startThroughputTimer();
      final rxStream = _rxEngine.startListening();
      _rxSubscription = rxStream.listen((msg) {
        _lastSnr = msg.snr;
        addDecodedMessage(msg);
      }, onError: (err) {
        print('RX stream error: $err');
      });
    }
    notifyListeners();
  }

  void addMessage(String msg, double snr) {
    _messages.insert(
      0,
      '[${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}] "$msg" (SNR: ${snr.toStringAsFixed(1)} dB)',
    );
    if (_messages.length > 100) _messages.removeLast();
    notifyListeners();
  }

  /// Reports (in [transferError]) and returns true when the current modem
  /// settings cannot carry any frame, instead of failing deep in the FFI.
  bool _rejectUnsendableConfig() {
    _transferError = _txEngine.frameLimitError;
    if (_transferError == null) return false;
    notifyListeners();
    return true;
  }

  Future<void> sendCurrentMessage() async {
    if (_txMessage.isEmpty) return;
    if (_rejectUnsendableConfig()) return;
    _isTransmitting = true;
    _metrics = _metrics.copyWith(connectionState: ModemLinkState.transmitting);
    _startThroughputTimer();
    notifyListeners();
    try {
      await _txQueue.enqueue(_txMessage);
      _txMessage = '';
    } catch (e) {
      print('Failed to send message: $e');
    } finally {
      _isTransmitting = false;
      _metrics = _metrics.copyWith(
        connectionState:
            _isListening ? ModemLinkState.listening : ModemLinkState.idle,
      );
      if (!_isListening) {
        _stopThroughputTimer();
      }
      notifyListeners();
    }
  }

  /// Sends [data] as a file through the TX queue. With ARQ on, starts
  /// listening first so the receiver's ACKs can be heard.
  Future<void> sendFileBytes(Uint8List data,
      {required String fileName, String? mimeType}) async {
    if (_rejectUnsendableConfig()) return;
    if (_arqEnabled && !_isListening) toggleListening();
    _isTransmitting = true;
    _metrics = _metrics.copyWith(connectionState: ModemLinkState.transmitting);
    _startThroughputTimer();
    notifyListeners();
    try {
      await _txQueue.enqueueFile(data,
          fileName: fileName,
          mimeType: mimeType ?? mimeTypeForFileName(fileName));
    } catch (e) {
      _transferError = '$e';
    } finally {
      _isTransmitting = false;
      _metrics = _metrics.copyWith(
        connectionState:
            _isListening ? ModemLinkState.listening : ModemLinkState.idle,
      );
      if (!_isListening) {
        _stopThroughputTimer();
      }
      notifyListeners();
    }
  }

  /// Aborts the outgoing fragmented transfer.
  void cancelTransfer() => _txEngine.cancelTransfer();

  Future<void> emitTestTone() async {
    final samples =
        TestToneGenerator.generateSine(440, 1.0, _sampleRate.toDouble());
    await _audio.startPlayback();
    await _audio.enqueueForPlayback(samples);
  }

  Future<void> emitChirp() async {
    final samples = TestToneGenerator.generateChirp(
      _carrierFreq - _bandwidth / 2,
      _carrierFreq + _bandwidth / 2,
      symbolDuration,
      _sampleRate.toDouble(),
    );
    await _audio.startPlayback();
    await _audio.enqueueForPlayback(samples);
  }

  Future<void> sendPresetMessage(String text) async {
    if (_rejectUnsendableConfig()) return;
    _isTransmitting = true;
    _metrics = _metrics.copyWith(connectionState: ModemLinkState.transmitting);
    _startThroughputTimer();
    notifyListeners();
    try {
      await _txQueue.enqueue(text);
    } finally {
      _isTransmitting = false;
      _metrics = _metrics.copyWith(
        connectionState:
            _isListening ? ModemLinkState.listening : ModemLinkState.idle,
      );
      if (!_isListening) {
        _stopThroughputTimer();
      }
      notifyListeners();
    }
  }

  void resetMetrics() {
    _throughputCalculator.reset();
    _rxEngine.resetStats();
    _txEngine.resetStats();
    _stopThroughputTimer();
    _metrics = SignalMetrics(
      connectionState: _isListening
          ? ModemLinkState.listening
          : (_isTransmitting
              ? ModemLinkState.transmitting
              : ModemLinkState.idle),
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
  }

  void loadPreset(String name) {
    switch (name) {
      case 'default':
        _mode = 0;
        _sf = 8;
        _numSubcarriers = 256;
        _cpLength = 64;
        _carrierFreq = 19000.0;
        _bandwidth = 2000.0;
        break;
      case 'long_range':
        _mode = 0;
        _sf = FrameGeometry.maxSf; // 0.51 s chirps, ~20 bit/s at 2 kHz
        _carrierFreq = 18000.0;
        _bandwidth = 2000.0;
        break;
      case 'high_speed':
        // OFDM occupies carrier +- bandwidth/2: 18-21 kHz (inaudible band,
        // one subcarrier of guard below Nyquist at 44.1 kHz).
        _mode = 1;
        _numSubcarriers = 2048;
        _cpLength = 128;
        _carrierFreq = 19500.0;
        _bandwidth = 3000.0;
        break;
    }
    _syncConfigMap();
    _audio.updateConfig(_configMap);
    _persist();
    notifyListeners();
  }

  Stream<Float64List> get audioStream => _audio.audioStream;

  /// Equalized OFDM constellation of received frames (while listening).
  Stream<ConstellationFrame> get constellationStream => _rxEngine.constellation;
  bool get isAudioCapturing => _audio.isCapturing;

  Future<void> startAudioCapture() async {
    await _audio.startCapture();
    notifyListeners();
  }

  Future<void> stopAudioCapture() async {
    await _audio.stopCapture();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // WAV recording, message export, signal samples and import (#33)
  // ---------------------------------------------------------------------

  /// Where recordings, exports and signal samples are written.
  SoundwaveStorage storage = SoundwaveStorage();

  /// Decoder for imported signals (real RX pipeline on a background isolate).
  SignalDecoder signalDecoder = OfflineDecoder.decodeInBackground;

  /// Recent capture audio kept for "Save Signal Sample" (10 s at 48 kHz).
  static const int recentAudioCapacity = 10 * 48000;

  final List<MessageRecord> _messageRecords = [];
  final RollingSampleBuffer _recentAudio =
      RollingSampleBuffer(recentAudioCapacity);
  StreamSubscription<Float64List>? _captureTap;
  WavRecorder? _wavRecorder;
  bool _recordingStarting = false;
  File? _lastRecording;

  /// Decoded messages, newest first, with the mode they were received in.
  List<MessageRecord> get messageRecords => List.unmodifiable(_messageRecords);
  bool get isRecording => _wavRecorder != null;
  String? get activeRecordingPath => _wavRecorder?.path;
  Duration get recordingDuration => _wavRecorder?.duration ?? Duration.zero;
  File? get lastRecording => _lastRecording;
  bool get hasRecentAudio => !_recentAudio.isEmpty;
  String get modeName => _mode == 1 ? 'OFDM' : 'CSS';

  void _onCapturedAudio(Float64List chunk) {
    final wasEmpty = _recentAudio.isEmpty;
    _recentAudio.add(chunk);
    _wavRecorder?.addSamples(chunk);
    // [hasRecentAudio] only changes on the first non-empty chunk; notify then
    // (so "Save Signal Sample" enables) rather than on every audio chunk.
    if (wasEmpty && !_recentAudio.isEmpty && !_isDisposed) notifyListeners();
  }

  /// Records captured audio to
  /// `recordings/soundwave_recording_YYYYMMDD_HHmmss.wav` until
  /// [stopRecording] (or until listening stops). Returns the file path.
  Future<String> startRecording() async {
    if (_wavRecorder != null || _recordingStarting) {
      throw StateError('A recording is already in progress');
    }
    _recordingStarting = true;
    try {
      final dir = await storage.directory(StorageArea.recordings);
      final recorder = WavRecorder(sampleRate: _sampleRate);
      final path = await recorder.startRecording(dir);
      if (_isDisposed) {
        await recorder.stopRecording();
        return path;
      }
      _wavRecorder = recorder;
      notifyListeners();
      return path;
    } finally {
      _recordingStarting = false;
    }
  }

  /// Finalises the WAV header and returns the file (null if not recording).
  Future<File?> stopRecording() async {
    final recorder = _wavRecorder;
    if (recorder == null) return null;
    _wavRecorder = null;
    notifyListeners();
    final file = await recorder.stopRecording();
    _lastRecording = file;
    notifyListeners();
    return file;
  }

  void _finishRecordingQuietly() {
    final recorder = _wavRecorder;
    if (recorder == null) return;
    _wavRecorder = null;
    recorder.stopRecording().then<void>(
      (file) {
        _lastRecording = file;
        notifyListeners();
      },
      onError: (Object e) => debugPrint('Failed to finalise recording: $e'),
    );
  }

  /// Logs a decoded message and keeps its full record for export.
  void addDecodedMessage(
    DecodedMessage msg, {
    String? mode,
    String logPrefix = '',
  }) {
    final record = MessageRecord.fromDecoded(msg, mode: mode ?? modeName);
    _messageRecords.insert(0, record);
    if (_messageRecords.length > 100) _messageRecords.removeLast();
    addMessage('$logPrefix${msg.text}', msg.snr);
  }

  /// Writes all decoded messages (oldest first) to `exports/`.
  Future<File> exportMessages(ExportFormat format) async {
    final dir = await storage.directory(StorageArea.exports);
    final chronological = _messageRecords.reversed.toList();
    return const MessageExporter().export(chronological, format, dir);
  }

  /// Saves the recent capture audio plus a metadata sidecar (with the latest
  /// decoded message, if any) to `samples/`.
  Future<SavedSignalSample> saveSignalSample({String note = ''}) {
    final latest = _messageRecords.isEmpty ? null : _messageRecords.first;
    return SignalSampleStore(storage).save(
      _recentAudio.snapshot(),
      sampleRate: _sampleRate,
      note: note,
      message: latest,
    );
  }

  /// Runs an imported signal through the RX pipeline with the current modem
  /// settings and logs every decoded message.
  Future<List<DecodedMessage>> decodeImportedSignal(
    ImportedSignal signal,
  ) async {
    final config = Map<String, dynamic>.from(_configMap);
    final mode = config['modulation'] == 1 ? 'OFDM' : 'CSS';
    final decoded = await signalDecoder(
      signal.samples,
      config,
      signal.sampleRate,
    );
    for (final m in decoded) {
      addDecodedMessage(m, mode: mode, logPrefix: '[file] ');
    }
    return decoded;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopThroughputTimer();
    _rxSubscription?.cancel();
    _rxFrameEventsSubscription?.cancel();
    _txMetricsSubscription?.cancel();
    for (final s in _linkSubscriptions) {
      s.cancel();
    }
    _txEngine.cancelTransfer();
    _transferNotices.close();
    _captureTap?.cancel();
    _finishRecordingQuietly();
    _rxEngine.stopListening();
    super.dispose();
  }
}
