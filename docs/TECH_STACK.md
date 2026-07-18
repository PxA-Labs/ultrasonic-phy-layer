# Technology Stack Specification

**Project:** Soundwave — Ultrasonic Physical Layer
**Version:** 1.0
**Date:** July 18, 2026
**Author:** PxA Labs (Archit Mittal, Purvansh Joshi)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                      │
│              (Dart — Material 3 Widgets)                │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Spectrum Analyzer  │  Constellation Diagram     │   │
│  │  Settings Panel     │  Connection Status         │   │
│  │  Waterfall Plot     │  Throughput Display        │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────┬──────────────────────────────────┘
                       │ dart:ffi (zero-copy, no serialization)
┌──────────────────────┴──────────────────────────────────┐
│                 C/C++ DSP Core Library                   │
│              (libsoundwave.so / .dll / .dylib)           │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Encoder: Reed-Solomon FEC + CRC-32              │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Modulator: CSS Chirp + OFDM IDFT/DFT            │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Synchronizer: ZC Preamble + Schmidl-Cox CFO     │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Demodulator: Channel Estimation + Equalization   │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Decoder: RS Decode + CRC Verify                  │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Audio I/O: miniaudio (cross-platform backends)   │   │
│  │   Android: AAudio / OpenSL ES                    │   │
│  │   macOS: CoreAudio                               │   │
│  │   Windows: WASAPI                                │   │
│  │   Linux: ALSA / PulseAudio / PipeWire            │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Core Technologies

### 2.1 Application Framework

| Component | Technology | Version | Rationale |
|---|---|---|---|
| **UI Framework** | Flutter | 3.41+ (stable) | Single codebase for Android + all desktop platforms, Impeller rendering engine, strong Google backing |
| **Language (UI)** | Dart | 3.11+ | Strongly-typed, null-safe, FFI support, gentle learning curve |
| **Language (DSP)** | C/C++ | C17 / C++17 | Maximum performance for real-time audio processing, direct hardware access |
| **Build System** | CMake | 3.22+ | Cross-platform C/C++ build, Flutter FFI integration |

### 2.2 DSP Libraries

| Library | Purpose | License | Rationale |
|---|---|---|---|
| **KissFFT** | FFT/IFFT operations | BSD-like | ~500 LOC, MIT-compatible, used by cyrinx for ultrasonic OFDM, supports float/double/int16/int32 |
| **miniaudio** | Cross-platform audio I/O | Public domain (MIT-0) | Single-file C library, pull-mode with ring buffers, supports AAudio/CoreAudio/WASAPI/ALSA |
| **pffft** | SIMD-optimized FFT (optional) | BSD | SSE/AVX/NEON acceleration, fallback for max performance |

### 2.3 Flutter Packages

| Package | Purpose | Rationale |
|---|---|---|
| `ffi` | Dart FFI bindings | Zero-copy C/C++ function calls |
| `ffigen` | FFI code generator | Auto-generates Dart bindings from C headers |
| `flutter_soloud` | Audio engine reference | Demonstrates C++ FFI audio pattern with FFT |
| `flutter_miniaudio` | Audio I/O reference | Pull-mode audio with lock-free ring buffers |
| `open_dspc` | DSP utilities | FFT backends, filtering, convolution |
| `path_provider` | File system paths | Platform-appropriate temp/cache directories |
| `permission_handler` | Audio permission requests | Microphone access on all platforms |
| `google_fonts` | Typography | Consistent cross-platform font rendering |

---

## 3. DSP Core Implementation

### 3.1 Module Structure

```
native/
├── CMakeLists.txt              # Top-level CMake build
├── include/
│   └── soundwave/
│       ├── soundwave.h         # Public API (exported to Flutter FFI)
│       ├── encoder.h           # RS encoder/decoder
│       ├── modulator.h         # CSS chirp + OFDM generation
│       ├── synchronizer.h      # Preamble detection + CFO
│       ├── demodulator.h       # FFT + equalization
│       ├── audio_io.h          # miniaudio wrapper
│       └── types.h             # Shared data structures
├── src/
│   ├── encoder.c               # Reed-Solomon + CRC-32
│   ├── modulator.c             # Chirp LFM + OFDM IDFT
│   ├── synchronizer.c          # ZC correlation + Schmidl-Cox
│   ├── demodulator.c           # FFT + LS/MMSE equalizer
│   ├── audio_io.c              # miniaudio pull-mode + ring buffer
│   ├── kiss_fft.c              # Vendored KissFFT
│   └── miniaudio.h             # Vendored miniaudio (single header)
└── tests/
    ├── test_encoder.c          # RS encode/decode golden vectors
    ├── test_modulator.c        # Chirp + OFDM golden vectors
    ├── test_fft.c              # FFT accuracy validation
    └── test_sync.c             # Preamble detection tests
```

### 3.2 Key API Surface

```c
// Public FFI API (soundwave.h)

// Lifecycle
sw_context* sw_create(sw_config config);
void        sw_destroy(sw_context* ctx);

// Encoder
sw_buffer  sw_encode(sw_context* ctx, const uint8_t* data, size_t len);
sw_buffer  sw_decode(sw_context* ctx, const uint8_t* encoded, size_t len);

// Modulator
sw_signal  sw_modulate_css(sw_context* ctx, const sw_buffer* bits);
sw_signal  sw_modulate_ofdm(sw_context* ctx, const sw_buffer* bits);

// Demodulator
sw_buffer  sw_demodulate(sw_context* ctx, const float* samples, size_t len);

// Audio I/O
int         sw_audio_start(sw_context* ctx, sw_audio_callback cb);
void        sw_audio_stop(sw_context* ctx);

// Diagnostics
float       sw_get_snr(sw_context* ctx);
float       sw_get_ber(sw_context* ctx);
sw_spectrum sw_get_spectrum(sw_context* ctx);
```

### 3.3 Data Types

```c
typedef struct {
    float   carrier_freq;       // Hz (18000-22000)
    float   bandwidth;          // Hz
    float   sample_rate;        // Hz (44100)
    int     symbol_rate;        // symbols/sec
    int     modulation;         // 0=CSS, 1=OFDM
    int     ofdm_subcarriers;   // e.g., 128
    int     cp_length;          // Cyclic prefix samples
    int     rs_n;               // RS block length
    int     rs_k;               // RS message length
} sw_config;

typedef struct {
    float*  data;
    size_t  length;
    float   sample_rate;
} sw_signal;

typedef struct {
    uint8_t* data;
    size_t   length;
} sw_buffer;

typedef struct {
    float*  magnitudes;
    size_t  num_bins;
    float   min_freq;
    float   max_freq;
} sw_spectrum;
```

---

## 4. Flutter UI Layer

### 4.1 Project Structure

```
lib/
├── main.dart                   # App entry point
├── app.dart                    # MaterialApp configuration
├── core/
│   ├── ffi_bindings.dart       # Generated FFI bindings (ffigen)
│   ├── soundwave_bridge.dart   # Dart wrapper around C API
│   └── audio_service.dart      # Audio I/O service layer
├── models/
│   ├── config.dart             # PHY configuration model
│   ├── signal_data.dart        # Spectrum/constellation data
│   └── transfer_result.dart    # Encode/decode results
├── screens/
│   ├── home_screen.dart        # Main dashboard
│   ├── transmitter_screen.dart # Send data UI
│   ├── receiver_screen.dart    # Receive data UI
│   └── settings_screen.dart    # Configuration UI
├── widgets/
│   ├── spectrum_analyzer.dart  # Real-time FFT visualization
│   ├── waterfall_plot.dart     # Spectrogram waterfall
│   ├── constellation_diagram.dart  # IQ constellation
│   ├── chirp_visualizer.dart   # Chirp waveform display
│   └── throughput_meter.dart   # Data rate indicator
└── utils/
    ├── permissions.dart        # Audio permission handling
    └── platform.dart           # Platform detection helpers
```

### 4.2 UI Components

| Widget | Description | Update Rate |
|---|---|---|
| `SpectrumAnalyzer` | Real-time FFT magnitude plot | 30 FPS |
| `WaterfallPlot` | Scrolling spectrogram history | 15 FPS |
| `ConstellationDiagram` | IQ scatter plot for OFDM symbols | On sync |
| `ChirpVisualizer` | Time-domain chirp waveform | On transmit |
| `ThroughputMeter` | Current data rate display | 1 Hz |
| `ConnectionStatus` | TX/RX/Sync state indicator | Event-driven |

---

## 5. Platform Configuration

### 5.1 Android

```gradle
// android/app/build.gradle
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 26  // Android 8.0
        targetSdkVersion 34
    }
    externalNativeBuild {
        cmake {
            arguments "-DANDROID_STL=c++_shared"
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86_64'
        }
    }
}
```

### 5.2 Windows

```cmake
# windows/CMakeLists.txt
cmake_minimum_required(VERSION 3.14)
target_link_libraries(${TARGET_NAME} PRIVATE
    soundwave
    wsapi32
    ole32
)
```

### 5.3 macOS

```ruby
# macos/Podfile
platform :osx, '12.0'
target 'Runner' do
  pod 'AudioToolbox'  # CoreAudio access
end
```

### 5.4 Linux

```cmake
# linux/CMakeLists.txt
find_package(ALSA REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSEAUDIO IMPORTED_TARGET libpulse-simple)
target_link_libraries(${TARGET_NAME} PRIVATE
    soundwave
    ALSA::ALSA
    PkgConfig::PULSEAUDIO
)
```

---

## 6. Build Configuration

### 6.1 CMake (DSP Core)

```cmake
cmake_minimum_required(VERSION 3.22)
project(soundwave VERSION 1.0.0 LANGUAGES C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# KissFFT (vendored)
add_library(kiss_fft STATIC vendor/kissfft/kiss_fft.c)
target_include_directories(kiss_fft PUBLIC vendor/kissfft)

# miniaudio (vendored, header-only)
add_library(miniaudio INTERFACE)
target_include_directories(miniaudio INTERFACE vendor/miniaudio)

# DSP Core library
add_library(soundwave STATIC
    src/encoder.c
    src/modulator.c
    src/synchronizer.c
    src/demodulator.c
    src/audio_io.c
)
target_include_directories(soundwave PUBLIC include)
target_link_libraries(soundwave PRIVATE kiss_fft miniaudio)

# Shared library for FFI
add_library(soundwave_shared SHARED $<TARGET_OBJECTS:soundwave>)
set_target_properties(soundwave_shared PROPERTIES
    OUTPUT_NAME "soundwave"
    PREFIX "lib"
)
```

---

## 7. Dependency Summary

| Category | Dependency | Version | License |
|---|---|---|---|
| Framework | Flutter | 3.41+ | BSD-3 |
| Language | Dart | 3.11+ | BSD-3 |
| Language | C/C++ (C17/C++17) | — | — |
| FFT | KissFFT | Latest | BSD-like |
| Audio I/O | miniaudio | Latest | Public domain |
| Build | CMake | 3.22+ | BSD-3 |
| FFI | dart:ffi | Built-in | BSD-3 |
| Codegen | ffigen | 12.0+ | BSD-3 |
| Testing | flutter_test | Built-in | BSD-3 |
| Testing | CTest | Built-in | BSD-3 |

---

## 8. Version Control

| Item | Configuration |
|---|---|
| Repository | `https://github.com/PxA-Labs/ultrasonic-phy-layer` |
| Branch strategy | `main` (production), `develop` (integration), feature branches |
| Commit convention | Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`) |
| PR reviews | Required minimum 1 approval |
| CI/CD | GitHub Actions (see CI_CD.md) |

---

## 9. Security Considerations

| Concern | Mitigation |
|---|---|
| No network permissions required | Air-gapped operation by default |
| Audio data not persisted | Process in-memory only, no disk writes |
| No telemetry | Zero analytics, crash reporting opt-in only |
| Supply chain | Pin dependency versions, audit vendored C code |
| Buffer overflow | Bounds checking on all FFI boundaries |

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-07-18 | PxA Labs | Initial tech stack specification |
