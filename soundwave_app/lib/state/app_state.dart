// App state — ChangeNotifier-based reactive state for the whole application.
// Holds modem config, TX/RX status, and received messages.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:soundwave/engine/tx_engine.dart';
import 'package:soundwave/engine/rx_engine.dart';
import 'package:soundwave/engine/tx_queue.dart';
import 'package:soundwave/services/audio_service.dart';

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
  StreamSubscription<DecodedMessage>? _rxSubscription;

  Map<String, dynamic> get configMap => {
        'sample_rate': _sampleRate,
        'modulation': _mode,
        'sf': _sf,
        'num_subcarriers': _numSubcarriers,
        'cp_length': _cpLength,
        'num_pilots': _numPilots,
        'carrier_freq': _carrierFreq,
        'bandwidth': _bandwidth,
        'symbol_duration': _symbolDuration,
        'amplitude': _amplitude,
        'ofdm_modulation': _ofdmModulation,
        'threshold': _threshold,
        'equalizer': _equalizer,
        'coding_rate': _codingRate,
        'enable_rs': _enableRs,
        'volume': _volume,
      };

  AppState({AudioService? audio}) {
    _audio = audio ?? AudioService.preferred(configMap);
    _txEngine =
        TxEngine(audio: _audio, configMap: configMap, useIsolates: false);
    _rxEngine =
        RxEngine(audio: _audio, configMap: configMap, useIsolates: false);
    _txQueue = TxQueue(txEngine: _txEngine);

    // Prepopulate audio devices
    if (_audio.inputDevices.isNotEmpty) {
      _inputDevice = _audio.inputDevices.first;
    }
    if (_audio.outputDevices.isNotEmpty) {
      _outputDevice = _audio.outputDevices.first;
    }
  }

  // Getters
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

  AudioDevice? get inputDevice => _inputDevice;
  AudioDevice? get outputDevice => _outputDevice;
  List<AudioDevice> get inputDevices => _audio.inputDevices;
  List<AudioDevice> get outputDevices => _audio.outputDevices;

  bool get isListening => _isListening;
  double get lastSnr => _lastSnr;
  String get txMessage => _txMessage;
  List<String> get messages => List.unmodifiable(_messages);
  bool get isTransmitting => _isTransmitting;

  // Setters
  set txMessage(String v) {
    _txMessage = v;
    notifyListeners();
  }

  void setMode(int m) {
    _mode = m;
    notifyListeners();
  }

  void setSf(int v) {
    _sf = v;
    notifyListeners();
  }

  void setNumSubcarriers(int v) {
    _numSubcarriers = v;
    notifyListeners();
  }

  void setCpLength(int v) {
    _cpLength = v;
    notifyListeners();
  }

  void setNumPilots(int v) {
    _numPilots = v;
    notifyListeners();
  }

  void setCarrierFreq(double v) {
    _carrierFreq = v;
    notifyListeners();
  }

  void setBandwidth(double v) {
    _bandwidth = v;
    notifyListeners();
  }

  void setSymbolDuration(double v) {
    _symbolDuration = v;
    notifyListeners();
  }

  void setAmplitude(double v) {
    _amplitude = v;
    notifyListeners();
  }

  void setOfdmModulation(int v) {
    _ofdmModulation = v;
    notifyListeners();
  }

  void setThreshold(double v) {
    _threshold = v;
    notifyListeners();
  }

  void setEqualizer(int v) {
    _equalizer = v;
    notifyListeners();
  }

  void setCodingRate(double v) {
    _codingRate = v;
    notifyListeners();
  }

  void setEnableRs(bool v) {
    _enableRs = v;
    notifyListeners();
  }

  void setVolume(double v) {
    _volume = v;
    notifyListeners();
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
    } else {
      _isListening = true;
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
    notifyListeners();
    try {
      await _txQueue.enqueue(_txMessage);
      _txMessage = '';
    } catch (e) {
      print('Failed to send message: $e');
    } finally {
      _isTransmitting = false;
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
    notifyListeners();
    try {
      await _txQueue.enqueue(text);
    } finally {
      _isTransmitting = false;
      notifyListeners();
    }
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
  void dispose() {
    _rxSubscription?.cancel();
    _rxEngine.stopListening();
    super.dispose();
  }
}
