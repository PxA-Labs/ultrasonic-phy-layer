// App state — ChangeNotifier-based reactive state for the whole application.
// Holds modem config, TX/RX status, and received messages.

import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  // Modem config
  int _sampleRate = 44100;
  int _mode = 0; // 0=CSS, 1=OFDM
  int _sf = 8;
  int _numSubcarriers = 256;
  int _cpLength = 64;
  int _numPilots = 8;

  // TX/RX state
  bool _isListening = false;
  double _lastSnr = 0.0;
  String _txMessage = '';
  final List<String> _messages = [];

  // Getters
  int get sampleRate => _sampleRate;
  int get mode => _mode;
  int get sf => _sf;
  int get numSubcarriers => _numSubcarriers;
  int get cpLength => _cpLength;
  int get numPilots => _numPilots;
  bool get isListening => _isListening;
  double get lastSnr => _lastSnr;
  String get txMessage => _txMessage;
  List<String> get messages => List.unmodifiable(_messages);

  set txMessage(String v) { _txMessage = v; }

  void setMode(int m) { _mode = m; notifyListeners(); }
  void setSf(int v) { _sf = v; notifyListeners(); }
  void setNumSubcarriers(int v) { _numSubcarriers = v; notifyListeners(); }

  void toggleListening() {
    _isListening = !_isListening;
    notifyListeners();
  }

  void addMessage(String msg, double snr) {
    _messages.insert(0, '[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] "$msg" (SNR: ${snr.toStringAsFixed(1)} dB)');
    if (_messages.length > 100) _messages.removeLast();
    notifyListeners();
  }

  void loadPreset(String name) {
    switch (name) {
      case 'default':
        _mode = 0; _sf = 8; _numSubcarriers = 256; _cpLength = 64;
        break;
      case 'long_range':
        _mode = 0; _sf = 12;
        break;
      case 'high_speed':
        _mode = 1; _numSubcarriers = 2048;
        break;
    }
    notifyListeners();
  }
}
