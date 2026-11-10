// App state — ChangeNotifier-based reactive state for the whole application.
// Holds modem config, TX/RX status, real-time signal metrics, and received messages.
// Follows OpenSSF secure coding guidelines with robust bounds checks and lifecycle cleanup.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/tx_queue.dart';
import 'package:soundwave/engine/signal_metrics.dart';
import 'package:soundwave/engine/throughput_calculator.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/state/settings_store.dart';

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
  double _symbolDuration = 0.02; // CSS symbol/chirp duration
  double _amplitude = 0.8;
  int _ofdmModulation = 1; // QPSK
  double _threshold = 3.0;
  int _equalizer = 0; // 0 = ZF, 1 = MMSE
  double _codingRate = 0.5;
  bool _enableRs = true;
  double _volume = 0.8;
  bool _agcEnabled = true; // RX automatic gain control (#92)

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
    _configMap['symbol_duration'] = _symbolDuration;
    _configMap['amplitude'] = _amplitude;
    _configMap['ofdm_modulation'] = _ofdmModulation;
    _configMap['threshold'] = _threshold;
    _configMap['equalizer'] = _equalizer;
    _configMap['coding_rate'] = _codingRate;
    _configMap['enable_rs'] = _enableRs;
    _configMap['volume'] = _volume;
    _configMap['agc_enabled'] = _agcEnabled;
  }

  AppState({AudioService? audio, SettingsStore? store}) : _store = store {
    _configMap = {};
    _syncConfigMap();
    _audio = audio ?? AudioService.preferred(_configMap);
    _txEngine =
        TxEngine(audio: _audio, configMap: _configMap, useIsolates: false);
    _rxEngine =
        RxEngine(audio: _audio, configMap: _configMap, useIsolates: false);
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
  double get symbolDuration => _symbolDuration;
  double get amplitude => _amplitude;
  int get ofdmModulation => _ofdmModulation;
  double get threshold => _threshold;
  int get equalizer => _equalizer;
  double get codingRate => _codingRate;
  bool get enableRs => _enableRs;
  double get volume => _volume;
  bool get agcEnabled => _agcEnabled;

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
    _symbolDuration = v['symbol_duration'] as double? ?? _symbolDuration;
    _amplitude = v['amplitude'] as double? ?? _amplitude;
    _ofdmModulation = v['ofdm_modulation'] as int? ?? _ofdmModulation;
    _threshold = v['threshold'] as double? ?? _threshold;
    _equalizer = v['equalizer'] as int? ?? _equalizer;
    _codingRate = v['coding_rate'] as double? ?? _codingRate;
    _enableRs = v['enable_rs'] as bool? ?? _enableRs;
    _volume = v['volume'] as double? ?? _volume;
    _agcEnabled = v['agc_enabled'] as bool? ?? _agcEnabled;
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

  void setSymbolDuration(double v) {
    _symbolDuration = v;
    _updateConfigField('symbol_duration', v);
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

  void setCodingRate(double v) {
    _codingRate = v;
    _updateConfigField('coding_rate', v);
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
        addMessage(msg.text, msg.snr);
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

  Future<void> sendCurrentMessage() async {
    if (_txMessage.isEmpty) return;
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

  Future<void> emitTestTone() async {
    final samples =
        TestToneGenerator.generateSine(440, 1.0, _sampleRate.toDouble());
    await _audio.enqueueForPlayback(samples);
    await _audio.startPlayback();
  }

  Future<void> emitChirp() async {
    final samples = TestToneGenerator.generateChirp(
      _carrierFreq - _bandwidth / 2,
      _carrierFreq + _bandwidth / 2,
      _symbolDuration,
      _sampleRate.toDouble(),
    );
    await _audio.enqueueForPlayback(samples);
    await _audio.startPlayback();
  }

  Future<void> sendPresetMessage(String text) async {
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
        _symbolDuration = 0.02;
        break;
      case 'long_range':
        _mode = 0;
        _sf = 12;
        _carrierFreq = 18000.0;
        _bandwidth = 1000.0;
        _symbolDuration = 0.05;
        break;
      case 'high_speed':
        _mode = 1;
        _numSubcarriers = 2048;
        _cpLength = 128;
        _carrierFreq = 19000.0;
        _bandwidth = 4000.0;
        break;
    }
    _syncConfigMap();
    _audio.updateConfig(_configMap);
    _persist();
    notifyListeners();
  }

  Stream<Float64List> get audioStream => _audio.audioStream;
  bool get isAudioCapturing => _audio.isCapturing;

  Future<void> startAudioCapture() async {
    await _audio.startCapture();
    notifyListeners();
  }

  Future<void> stopAudioCapture() async {
    await _audio.stopCapture();
    notifyListeners();
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
    _rxEngine.stopListening();
    super.dispose();
  }
}
