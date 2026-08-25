// RX Engine — captures audio, detects frames, demodulates, and decodes messages.
// Integrates real-time SignalMetrics and RxFrameEvents emission for live status tracking.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:soundwave/native/soundwave_native.dart';
import 'package:soundwave/native/bindings.dart';
import 'package:soundwave/services/audio_service.dart';
import 'package:soundwave/engine/signal_metrics.dart';

class DecodedMessage {
  final String text;
  final double snr;
  final DateTime timestamp;
  final Uint8List rawBytes;

  const DecodedMessage({
    required this.text,
    required this.snr,
    required this.timestamp,
    required this.rawBytes,
  });
}

class RxEngine {
  final SoundwaveNative? _native;
  final AudioService _audio;
  final Map<String, dynamic> _configMap;
  final bool _useIsolates;

  bool _isListening = false;
  final List<double> _sampleBuffer = [];
  final StreamController<DecodedMessage> _messageStreamController =
      StreamController<DecodedMessage>.broadcast();
  final StreamController<SignalMetrics> _metricsController =
      StreamController<SignalMetrics>.broadcast();
  final StreamController<RxFrameEvent> _frameEventsController =
      StreamController<RxFrameEvent>.broadcast();

  StreamSubscription<Float64List>? _audioSubscription;

  int _framesDetected = 0;
  int _framesReceived = 0;
  int _frameErrors = 0;
  int _totalBytesReceived = 0;
  double _lastSnr = 0.0;

  RxEngine({
    SoundwaveNative? native,
    required AudioService audio,
    required Map<String, dynamic> configMap,
    bool useIsolates = true,
  })  : _native = native,
        _audio = audio,
        _configMap = configMap,
        _useIsolates = useIsolates;

  SoundwaveNative get native => _native ?? SoundwaveNative.instance;

  Stream<DecodedMessage> get messages => _messageStreamController.stream;
  Stream<SignalMetrics> get metrics => _metricsController.stream;
  Stream<RxFrameEvent> get frameEvents => _frameEventsController.stream;

  bool get isListening => _isListening;
  int get framesDetected => _framesDetected;
  int get framesReceived => _framesReceived;
  int get frameErrors => _frameErrors;
  int get totalBytesReceived => _totalBytesReceived;
  double get lastSnr => _lastSnr;

  void _emitCurrentMetrics(ModemLinkState state) {
    if (_metricsController.isClosed) return;
    _metricsController.add(SignalMetrics(
      connectionState: state,
      snr: _lastSnr,
      totalBytesTransferred: _totalBytesReceived,
      framesReceived: _framesReceived,
      framesDetected: _framesDetected,
      frameErrors: _frameErrors,
      lastUpdated: DateTime.now(),
    ));
  }

  Stream<DecodedMessage> startListening() {
    if (_isListening) return _messageStreamController.stream;
    _isListening = true;
    _sampleBuffer.clear();
    _emitCurrentMetrics(ModemLinkState.listening);

    _audio.startCapture().then((_) {
      _audioSubscription = _audio.audioStream.listen((chunk) async {
        if (!_isListening) return;
        _sampleBuffer.addAll(chunk);

        // Process sliding window for frame detection
        // Frame sync search window: 44100 samples (1 second)
        const searchWindow = 44100;
        while (_sampleBuffer.length >= searchWindow) {
          final searchSlice = Float32List(searchWindow);
          for (int i = 0; i < searchWindow; i++) {
            searchSlice[i] = _sampleBuffer[i];
          }

          final configPtr = SwConfig.fromMap(_configMap);
          try {
            final syncRes = native.detectFrame(searchSlice, configPtr);
            final frameStart = syncRes['frame_start'] as int;
            final snr = (syncRes['snr'] as num).toDouble();

            if (frameStart >= 0) {
              // Frame found!
              _framesDetected++;
              _lastSnr = snr;
              _frameEventsController.add(RxFrameEvent(
                detected: true,
                decoded: false,
                snr: snr,
                byteLength: 0,
                timestamp: DateTime.now(),
              ));
              _emitCurrentMetrics(ModemLinkState.receiving);

              const frameLength = 17640;
              if (frameStart + frameLength <= _sampleBuffer.length) {
                final frameSamples = Float32List(frameLength);
                for (int i = 0; i < frameLength; i++) {
                  frameSamples[i] = _sampleBuffer[frameStart + i];
                }

                // Offload demodulation to background Isolate or run synchronously
                final Uint8List demodulatedBytes;
                if (_useIsolates) {
                  demodulatedBytes = await compute(_demodulateTask, {
                    'samples': frameSamples,
                    'config': _configMap,
                  });
                } else {
                  final configPtr2 = SwConfig.fromMap(_configMap);
                  try {
                    if (_configMap['modulation'] == 1) {
                      demodulatedBytes =
                          native.ofdmDemodulate(frameSamples, configPtr2);
                    } else {
                      demodulatedBytes =
                          native.cssDemodulate(frameSamples, configPtr2);
                    }
                  } finally {
                    calloc.free(configPtr2);
                  }
                }

                bool frameDecodedSuccessfully = false;

                if (demodulatedBytes.length > 36) {
                  final packet =
                      demodulatedBytes.sublist(0, demodulatedBytes.length - 32);
                  final parity =
                      demodulatedBytes.sublist(demodulatedBytes.length - 32);

                  try {
                    final decodeRes = native.rsDecode(packet, parity);
                    final correctedPacket = decodeRes['message'] as Uint8List;

                    if (correctedPacket.length > 4) {
                      final receivedCrc =
                          ByteData.sublistView(correctedPacket, 0, 4)
                              .getUint32(0, Endian.little);
                      final payload = correctedPacket.sublist(4);
                      final calculatedCrc = native.crc32(payload);

                      if (receivedCrc == calculatedCrc) {
                        frameDecodedSuccessfully = true;
                        _framesReceived++;
                        _totalBytesReceived += payload.length;

                        final text = utf8.decode(payload, allowMalformed: true);
                        final decodedMsg = DecodedMessage(
                          text: text,
                          snr: snr,
                          timestamp: DateTime.now(),
                          rawBytes: payload,
                        );

                        _messageStreamController.add(decodedMsg);
                        _frameEventsController.add(RxFrameEvent(
                          detected: true,
                          decoded: true,
                          snr: snr,
                          byteLength: payload.length,
                          timestamp: DateTime.now(),
                        ));
                        _emitCurrentMetrics(ModemLinkState.listening);
                      }
                    }
                  } catch (e) {
                    print(
                        'Demodulated frame RS decode/CRC verification failed: $e');
                  }
                }

                if (!frameDecodedSuccessfully) {
                  _frameErrors++;
                  _frameEventsController.add(RxFrameEvent(
                    detected: true,
                    decoded: false,
                    snr: snr,
                    byteLength: 0,
                    timestamp: DateTime.now(),
                    errorMessage: 'CRC / RS decoding check failed',
                  ));
                  _emitCurrentMetrics(ModemLinkState.error);
                }

                _sampleBuffer.removeRange(0, frameStart + frameLength);
                continue;
              } else {
                break;
              }
            }
          } catch (e) {
            print('Frame detection failed: $e');
          } finally {
            calloc.free(configPtr);
          }

          // Slide forward
          _sampleBuffer.removeRange(0, 4410);
        }
      }, onError: (err) {
        print('RX Engine audio stream error: $err');
      });
    });

    return _messageStreamController.stream;
  }

  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _audio.stopCapture();
    _emitCurrentMetrics(ModemLinkState.idle);
  }

  void resetStats() {
    _framesDetected = 0;
    _framesReceived = 0;
    _frameErrors = 0;
    _totalBytesReceived = 0;
    _lastSnr = 0.0;
    _emitCurrentMetrics(
        _isListening ? ModemLinkState.listening : ModemLinkState.idle);
  }
}

// Background demodulate task
Uint8List _demodulateTask(Map<String, dynamic> args) {
  final samples = args['samples'] as Float32List;
  final configMap = args['config'] as Map<String, dynamic>;

  final configPtr = SwConfig.fromMap(configMap);
  try {
    final nat = SoundwaveNative.instance;
    if (configMap['modulation'] == 1) {
      return nat.ofdmDemodulate(samples, configPtr);
    } else {
      return nat.cssDemodulate(samples, configPtr);
    }
  } finally {
    calloc.free(configPtr);
  }
}
