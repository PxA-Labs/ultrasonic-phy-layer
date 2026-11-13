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
import 'package:soundwave/engine/frame_codec.dart';
import 'package:soundwave/engine/frame_geometry.dart';
import 'package:soundwave/engine/agc_processor.dart';
import 'package:soundwave/dsp/constellation.dart';

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
  final StreamController<ConstellationFrame> _constellationController =
      StreamController<ConstellationFrame>.broadcast();

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

  /// Equalized OFDM constellation points of each frame that was decoded or
  /// given up on. Only computed while someone listens (it costs one extra
  /// demodulation per frame).
  Stream<ConstellationFrame> get constellation =>
      _constellationController.stream;

  /// Cap on constellation points per frame.
  static const int maxConstellationPoints = 4096;

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
      agcGainDb: agcGainDb,
      lastUpdated: DateTime.now(),
    ));
  }

  // ---------------------------------------------------------------------
  // Receive pipeline
  //
  // 1. SEARCH: run frame detection on a window sized from the active config
  //    (FrameGeometry). On a hit, drop everything before the frame start so
  //    the buffer begins at the preamble.
  // 2. DECODE: as audio keeps arriving, demodulate the buffer and let
  //    FrameCodec search for a frame length whose RS + CRC-32 verify. Short
  //    messages decode as soon as their last symbol arrives; attempts are
  //    spaced by [retryStepSymbols] symbols to bound CPU use.
  // 3. If nothing verifies by the longest possible frame, count a frame error
  //    and skip past the preamble.
  // ---------------------------------------------------------------------

  /// Symbols of new audio required between two decode attempts. Bounds CPU
  /// use (each attempt demodulates the whole pending frame) at the cost of up
  /// to this many symbols of extra latency (0.64 s CSS / 0.23 s OFDM default).
  static const int retryStepSymbols = 32;

  int? _pendingFrameSince; // buffer length at the last decode attempt
  double _pendingSnr = 0.0;
  bool _processing = false;

  FrameCodec get _codec => FrameCodec(native);
  bool get _agcEnabled => _configMap['agc_enabled'] as bool? ?? true;
  late final AgcProcessor _agc = AgcProcessor(native);

  /// Current AGC gain in dB, or null when AGC is disabled / not running.
  double? get agcGainDb => _agcEnabled && _agc.isActive ? _agc.gainDb : null;
  bool get _enableRs => _configMap['enable_rs'] as bool? ?? true;

  Stream<DecodedMessage> startListening() {
    if (_isListening) return _messageStreamController.stream;
    _isListening = true;
    _sampleBuffer.clear();
    _pendingFrameSince = null;
    _agc.reset();
    _emitCurrentMetrics(ModemLinkState.listening);

    _audio.startCapture().then((_) {
      _audioSubscription = _audio.audioStream.listen((chunk) async {
        if (!_isListening) return;
        // AGC normalises the level before detection/demodulation (#92).
        final sampleRate =
            (_configMap['sample_rate'] as num?)?.toInt() ?? 44100;
        _sampleBuffer.addAll(_agcEnabled
            ? _agc.process(chunk,
                sampleRate: sampleRate > 0 ? sampleRate : 44100)
            : chunk);
        await _processBuffer();
      }, onError: (err) {
        debugPrint('RX Engine audio stream error: $err');
      });
    });

    return _messageStreamController.stream;
  }

  /// Drains as much of the sample buffer as the current audio allows.
  /// Re-entrancy safe: chunks arriving during an await are picked up by the
  /// running loop.
  Future<void> _processBuffer() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_isListening) {
        final geometry = FrameGeometry.fromConfig(_configMap);
        final progressed = _pendingFrameSince == null
            ? _searchForFrame(geometry)
            : await _tryDecodePending(geometry);
        if (!progressed) break;
      }
    } finally {
      _processing = false;
    }
  }

  /// Returns true if the buffer changed and the loop should continue.
  bool _searchForFrame(FrameGeometry geometry) {
    final window = geometry.searchWindowSamples;
    if (_sampleBuffer.length < window) return false;

    final slice = Float32List(window);
    for (var i = 0; i < window; i++) {
      slice[i] = _sampleBuffer[i];
    }
    final configPtr = SwConfig.fromMap(_configMap);
    int frameStart = -1;
    double snr = 0.0;
    try {
      final res = native.detectFrame(slice, configPtr);
      frameStart = res['frame_start'] as int;
      snr = (res['snr'] as num).toDouble();
    } on SwException {
      frameStart = -1; // no preamble in this window
    } catch (e) {
      debugPrint('Frame detection failed: $e');
      frameStart = -1;
    } finally {
      calloc.free(configPtr);
    }

    if (frameStart < 0 || frameStart >= window) {
      // Keep the last preamble's worth so a preamble straddling the window
      // edge is still found on the next pass.
      _sampleBuffer.removeRange(0, window - geometry.preambleSamples);
      return true;
    }

    _framesDetected++;
    _lastSnr = snr.isFinite ? snr : 0.0;
    _pendingSnr = _lastSnr;
    _frameEventsController.add(RxFrameEvent(
      detected: true,
      decoded: false,
      snr: _lastSnr,
      byteLength: 0,
      timestamp: DateTime.now(),
    ));
    _emitCurrentMetrics(ModemLinkState.receiving);
    _sampleBuffer.removeRange(0, frameStart);
    _pendingFrameSince = 0;
    return true;
  }

  Future<bool> _tryDecodePending(FrameGeometry geometry) async {
    final available = _sampleBuffer.length;
    // Two symbols of slack: the OFDM demodulator only emits a symbol when
    // audio follows it, so the longest frame needs a little trailing audio.
    final maxFrame = geometry.maxFrameSamples + 2 * geometry.samplesPerSymbol;
    final step = retryStepSymbols * geometry.samplesPerSymbol;
    final reachedMax = available >= maxFrame;
    if (available < geometry.minFrameSamples) return false;
    if (!reachedMax &&
        available - _pendingFrameSince! < step &&
        _pendingFrameSince! > 0) {
      return false; // wait for more audio before trying again
    }

    final n = reachedMax ? maxFrame : available;
    final samples = Float32List(n);
    for (var i = 0; i < n; i++) {
      samples[i] = _sampleBuffer[i];
    }
    _pendingFrameSince = available;

    Uint8List bytes;
    try {
      bytes = await _demodulate(samples);
    } on SwException {
      bytes = Uint8List(0);
    } catch (e) {
      debugPrint('Demodulation failed: $e');
      bytes = Uint8List(0);
    }

    final frame = _codec.decode(bytes, enableRs: _enableRs);
    if (frame != null) {
      _onFrameDecoded(frame);
      final consumed = geometry.samplesForFrameBytes(frame.frameLength);
      _emitConstellation(
        consumed < n ? Float32List.sublistView(samples, 0, consumed) : samples,
        decoded: true,
      );
      _sampleBuffer.removeRange(0, consumed.clamp(0, _sampleBuffer.length));
      _pendingFrameSince = null;
      return true;
    }

    if (reachedMax) {
      _onFrameError();
      _emitConstellation(samples, decoded: false);
      _sampleBuffer.removeRange(
          0, geometry.preambleSamples.clamp(0, _sampleBuffer.length));
      _pendingFrameSince = null;
      return true;
    }
    return false;
  }

  Future<Uint8List> _demodulate(Float32List samples) async {
    if (_useIsolates) {
      return compute(_demodulateTask, {
        'samples': samples,
        'config': Map<String, dynamic>.from(_configMap),
      });
    }
    final configPtr = SwConfig.fromMap(_configMap);
    try {
      return _configMap['modulation'] == 1
          ? native.ofdmDemodulate(samples, configPtr)
          : native.cssDemodulate(samples, configPtr);
    } finally {
      calloc.free(configPtr);
    }
  }

  /// Publishes the equalized constellation of a frame-aligned OFDM frame.
  void _emitConstellation(Float32List frameSamples, {required bool decoded}) {
    if (!_constellationController.hasListener) return;
    if (_configMap['modulation'] != 1) return;
    final nat = native;
    if (!nat.hasEqualizedSymbols) return;
    final configPtr = SwConfig.fromMap(_configMap);
    try {
      final iq = nat.ofdmEqualizedSymbols(
        frameSamples,
        configPtr,
        maxPoints: maxConstellationPoints,
      );
      if (iq.isEmpty) return;
      final mapping = (_configMap['ofdm_modulation'] as num?)?.toInt() ?? 1;
      _constellationController.add(ConstellationFrame(
        iq: iq,
        scheme: ConstellationScheme.fromOfdmModulation(mapping),
        decoded: decoded,
      ));
    } on SwException {
      // No usable constellation for this frame; nothing to show.
    } catch (e) {
      debugPrint('Constellation extraction failed: $e');
    } finally {
      calloc.free(configPtr);
    }
  }

  void _onFrameDecoded(DecodedFrame frame) {
    _framesReceived++;
    _totalBytesReceived += frame.payload.length;
    final now = DateTime.now();
    _messageStreamController.add(DecodedMessage(
      text: utf8.decode(frame.payload, allowMalformed: true),
      snr: _pendingSnr,
      timestamp: now,
      rawBytes: frame.payload,
    ));
    _frameEventsController.add(RxFrameEvent(
      detected: true,
      decoded: true,
      snr: _pendingSnr,
      byteLength: frame.payload.length,
      timestamp: now,
    ));
    _emitCurrentMetrics(ModemLinkState.listening);
  }

  void _onFrameError() {
    _frameErrors++;
    _frameEventsController.add(RxFrameEvent(
      detected: true,
      decoded: false,
      snr: _pendingSnr,
      byteLength: 0,
      timestamp: DateTime.now(),
      errorMessage: 'CRC / RS decoding check failed',
    ));
    _emitCurrentMetrics(ModemLinkState.error);
  }

  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    _pendingFrameSince = null;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _audio.stopCapture();
    _agc.dispose(); // frees the native instance; recreated on next listen
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
