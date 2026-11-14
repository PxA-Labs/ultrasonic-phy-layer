# Dart API (Flutter app)

The complete, generated reference for every public library in `soundwave_app/lib/` is the **[dart doc output](dart/index.html)**. It is built by `dart doc` in the docs workflow, so it always matches the commit the site was built from.

`soundwave_app` is an application (`publish_to: none`), not a published package, so these APIs are internal and may change without notice. This page is a map of the most important types.

## Native bindings (`lib/native/`)

| Type | Purpose |
|---|---|
| `SoundwaveNative` | Singleton (`SoundwaveNative.instance`) that loads `libsoundwave` and wraps each `sw_*` function. On Android it loads `libsoundwave.so`. Desktop builds look next to the executable first (`soundwave.dll`, `../Frameworks/libsoundwave.dylib`, `lib/libsoundwave.so`), then development build folders. `$SOUNDWAVE_LIB` overrides the path. Errors are thrown as `SwException(code)` |
| `SwConfig` | `dart:ffi` `Struct` mirroring `sw_config_t` field for field. A helper converts the app's config map into a native struct |

Wrapper methods take and return Dart types such as `Uint8List` and `Float32List`. Buffers are sized with the C API's overflow protocol: try an estimate, and retry once with the size reported on `SW_ERR_OVERFLOW`.

## Engines (`lib/engine/`)

| Type | Purpose |
|---|---|
| `FrameCodec` | App frame format `[CRC-32][payload ≤ 219 B][RS parity 32 B]`. `encode` builds a frame. `decode` searches candidate lengths until RS + CRC verify |
| `FrameGeometry` | Samples per symbol and preamble, and bits per symbol, for a config. Mirrors the native modulators and sizes the RX buffers |
| `TxEngine` | Encodes text or files, modulates on a background isolate and queues audio. Uses the link layer for long messages, files and ARQ |
| `RxEngine` | Capture loop: AGC → `detectFrame` → demodulate → `FrameCodec.decode`, then hands link frames to `LinkReceiver`. Exposes `messages`, `transfers`, `constellation` and frame-event streams |
| `link_frame.dart` | DATA / ACK / NACK frame encoding (magic byte `0xFA`) and the message envelope (text or file, CRC-32, 1 MiB limit) |
| `PayloadFragmenter`, `PayloadReassembler` | Split envelopes into fragments of at most 208 B, and reassemble out-of-order fragments with duplicate suppression and idle timeouts |
| `ArqSender`, `ArqConfig` | Stop-and-wait ARQ with exponential backoff, jitter and NACK-triggered retransmission |
| `AgcProcessor` | Thin wrapper over the native AGC handle |
| `SignalMetrics`, `ThroughputCalculator`, `TxQueue` | Status bar metrics, throughput, and the transmit queue |

## Services, state and export

| Type | Purpose |
|---|---|
| `AudioService` | Interface. `NativeAudioService` (miniaudio through FFI) is preferred, and `RecordAudioService` (the `record` + `audioplayers` plugins) is the fallback |
| `MicPermission`, `MicPermissionGate` | Runtime microphone permission (Android/iOS only; desktop has no runtime prompt) and the first-run explanation UI |
| `AppState` | `ChangeNotifier` that holds modem settings, presets, the engines, message records, recording/export/import and file transfer state |
| `SettingsStore` | Persistence interface. `SharedPreferencesSettingsStore` is used in the app and `InMemorySettingsStore` in tests |
| `UiPreferences` | Theme mode and the onboarding-completed flag |
| `SoundwaveStorage`, `StorageArea` | `<app documents>/soundwave/{recordings,exports,samples}`, plus usage and clear operations |
| `WavRecorder`, `wav_format.dart` | Streaming 16-bit mono WAV writer, and WAV parsing (PCM 8/16/24/32-bit, float 32/64-bit) |
| `SignalImporter`, `OfflineDecoder` | Import `.wav`/`.pcm`/`.raw` files and decode them with the real RX pipeline on an isolate |
| `MessageExporter` | Export the message log as JSON, CSV or TXT |
| `DirectoryFileSink`, `sanitizeFileName` | Save received files safely (no path traversal, no overwrite) |
| `FileGateway` | `file_picker` (open) and `share_plus` (share) behind an interface, so tests can fake them |

## DSP for visualization (`lib/dsp/`)

`Fft`, `SpectrumAnalyzer` (Hann window, dBFS), `WaterfallBuffer` and `constellation.dart` (EVM and decision helpers) are pure Dart. They feed the Monitor screen only and are not part of the modem path.

## Regenerating locally

```bash
cd soundwave_app
flutter pub get
dart doc --output ../docs/api/dart .
```
