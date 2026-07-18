# Implementation Roadmap

**Project:** Soundwave — Ultrasonic Physical Layer
**Version:** 1.0
**Date:** July 18, 2026
**Author:** PxA Labs (Archit Mittal, Purvansh Joshi)

---

## 1. Roadmap Summary

| Phase | Duration | Focus | Milestone |
|---|---|---|---|
| **Phase 1** | Weeks 1–4 | DSP Core Foundation | C library compiles, golden vector tests pass |
| **Phase 2** | Weeks 5–8 | Flutter UI + FFI Integration | End-to-end CSS transmit/receive on desktop |
| **Phase 3** | Weeks 9–12 | OFDM + Advanced Features | OFDM mode working, spectrum analyzer UI |
| **Phase 4** | Weeks 13–16 | CI/CD + Platform Hardening | All platforms build, signed releases |
| **Phase 5** | Weeks 17–20 | Testing + Polish + Launch | App store submission, documentation |

**Total estimated duration:** 20 weeks (~5 months)

---

## 2. Phase 1 — DSP Core Foundation (Weeks 1–4)

**Goal:** Working C library with all PHY algorithms, validated by golden vector tests.

### Week 1: Project Scaffolding

- [ ] Initialize Flutter project with platform support (Android, Windows, macOS, Linux)
- [ ] Set up `native/` directory with CMake build system
- [ ] Vendor KissFFT and miniaudio
- [ ] Define public C API (`soundwave.h`)
- [ ] Set up CTest framework with Catch2

### Week 2: Encoder Module

- [ ] Implement CRC-32 computation (generator polynomial from MATHEMATICAL_MODEL.md)
- [ ] Implement Reed-Solomon encoder over GF(2^8)
- [ ] Implement Reed-Solomon decoder (Berlekamp-Massey or Euclidean algorithm)
- [ ] Write golden vector tests for RS encode/decode
- [ ] Write golden vector tests for CRC-32

### Week 3: Modulator Module

- [ ] Implement CSS chirp generation (LFM formula from MATHEMATICAL_MODEL.md)
- [ ] Implement OFDM subcarrier mapping (BPSK, QPSK)
- [ ] Implement OFDM IDFT using KissFFT
- [ ] Implement cyclic prefix insertion
- [ ] Write golden vector tests for chirp and OFDM signals

### Week 4: Demodulator & Synchronizer

- [ ] Implement Zadoff-Chu preamble generation
- [ ] Implement matched filter preamble detection
- [ ] Implement Schmidl-Cox CFO estimation
- [ ] Implement OFDM DFT demodulation
- [ ] Implement channel estimation (LS) and equalization (ZF, MMSE)
- [ ] Write integration test: encode → modulate → demodulate → decode (loopback)

### Phase 1 Deliverable
- `libsoundwave.so` / `.dll` / `.dylib` compiles on all platforms
- All golden vector tests pass
- Loopback test: text payload survives encode → modulate → demodulate → decode

---

## 3. Phase 2 — Flutter UI + FFI Integration (Weeks 5–8)

**Goal:** Functional Flutter app with CSS mode working end-to-end on desktop.

### Week 5: FFI Bridge

- [ ] Set up `ffigen` to generate Dart bindings from `soundwave.h`
- [ ] Implement `SoundwaveBridge` Dart class wrapping C API
- [ ] Handle memory management (allocate/free across FFI boundary)
- [ ] Write unit tests for FFI bridge layer

### Week 6: Audio I/O Integration

- [ ] Integrate miniaudio for desktop audio (WASAPI, CoreAudio, ALSA)
- [ ] Implement pull-mode audio callback with ring buffer
- [ ] Test speaker output and microphone input on desktop
- [ ] Implement audio permission handling per platform

### Week 7: Core UI

- [ ] Build home screen with TX/RX mode selector
- [ ] Build transmitter screen (text input → encode → transmit)
- [ ] Build receiver screen (receive → decode → display)
- [ ] Build settings panel (frequency, modulation, FEC config)
- [ ] Build connection status indicator

### Week 8: CSS End-to-End

- [ ] Integrate CSS modulator with Flutter audio output
- [ ] Integrate CSS demodulator with Flutter audio input
- [ ] Test CSS transmit/receive between two desktop instances
- [ ] Measure throughput and BER in lab conditions

### Phase 2 Deliverable
- Desktop app with CSS mode working end-to-end
- Text payload transmitted and received between two devices
- Settings panel for PHY configuration

---

## 4. Phase 3 — OFDM + Advanced Features (Weeks 9–12)

**Goal:** OFDM mode working, real-time visualizations, Android support.

### Week 9: OFDM Integration

- [ ] Integrate OFDM modulator with Flutter audio output
- [ ] Integrate OFDM demodulator with Flutter audio input
- [ ] Test OFDM transmit/receive between two desktop instances
- [ ] Measure OFDM throughput vs CSS

### Week 10: Spectrum Analyzer & Visualizations

- [ ] Implement real-time FFT visualization widget
- [ ] Implement waterfall plot (scrolling spectrogram)
- [ ] Implement constellation diagram for OFDM
- [ ] Implement chirp waveform visualizer
- [ ] Implement throughput meter

### Week 11: Android Support

- [ ] Configure Android NDK build for DSP core
- [ ] Test AAudio backend on Android devices
- [ ] Implement Android audio permission handling
- [ ] Build and test APK on physical Android devices
- [ ] Optimize for ARM NEON SIMD

### Week 12: Binary Payload Support

- [ ] Implement payload fragmentation (4 KB chunks)
- [ ] Implement reassembly with sequence numbering
- [ ] Add file picker for binary file transfer
- [ ] Add transfer progress indicator
- [ ] Test file transfer between devices

### Phase 3 Deliverable
- OFDM mode working end-to-end
- Real-time spectrum analyzer and visualizations
- Android APK functional on physical devices
- Binary file transfer supported

---

## 5. Phase 4 — CI/CD + Platform Hardening (Weeks 13–16)

**Goal:** Automated builds on all platforms, signed releases, deployment pipelines.

### Week 13: CI Pipeline

- [ ] Set up GitHub Actions quality gate workflow (ci.yml)
- [ ] Configure Dart analysis, formatting, and unit tests
- [ ] Configure C/C++ CTest in CI
- [ ] Set up Codecov integration

### Week 14: Build Matrix

- [ ] Set up Android build workflow (APK + AAB)
- [ ] Set up Windows build workflow (EXE/MSIX)
- [ ] Set up macOS build workflow (DMG)
- [ ] Set up Linux build workflow (DEB/AppImage)
- [ ] Configure build caching for all platforms

### Week 15: Signing & Deployment

- [ ] Generate and configure Android signing keystore
- [ ] Configure macOS code signing and notarization
- [ ] Configure Windows code signing
- [ ] Set up Play Store deployment (internal track)
- [ ] Set up GitHub Releases workflow
- [ ] Set up Snap Store deployment

### Week 16: Platform Hardening

- [ ] Test all builds on target OS versions
- [ ] Verify audio latency on each platform
- [ ] Optimize app startup time (< 2 seconds)
- [ ] Verify memory usage < 120 MB
- [ ] Test with various speaker/microphone hardware

### Phase 4 Deliverable
- All platforms build automatically in CI
- Signed releases for Android, Windows, macOS, Linux
- Deployment to Play Store (internal), GitHub Releases, Snap Store

---

## 6. Phase 5 — Testing + Polish + Launch (Weeks 17–20)

**Goal:** Production-quality release, documentation, app store submission.

### Week 17: Comprehensive Testing

- [ ] End-to-end BER testing across distances (1m, 3m, 5m, 8m)
- [ ] Range testing outdoors (line-of-sight)
- [ ] Multipath testing (indoor, reverberant rooms)
- [ ] Doppler testing (moving device)
- [ ] Stress testing (continuous 1-hour operation)
- [ ] Cross-device compatibility testing

### Week 18: Polish & UX

- [ ] Dark mode / light mode theming
- [ ] Onboarding tutorial
- [ ] Error handling and user feedback
- [ ] Accessibility (screen reader labels)
- [ ] Performance optimization (profiling, hotpath tuning)

### Week 19: Documentation

- [ ] User guide / README update
- [ ] Developer setup guide
- [ ] API documentation (C API + Dart API)
- [ ] Contributing guide update
- [ ] Privacy policy and terms of service

### Week 20: Launch

- [ ] Final QA pass on all platforms
- [ ] Submit APK to Google Play Store (beta → production)
- [ ] Publish GitHub Release (v1.0.0)
- [ ] Publish Snap to Snap Store
- [ ] Announce release (GitHub Discussions, social media)

### Phase 5 Deliverable
- v1.0.0 released on all platforms
- Documentation complete
- App store submission accepted

---

## 7. Milestone Summary

| Milestone | Target Date | Deliverable |
|---|---|---|
| M1: DSP Core Complete | End of Week 4 | `libsoundwave` with all PHY algorithms + golden vector tests |
| M2: Desktop CSS Working | End of Week 8 | Flutter app with CSS mode end-to-end on desktop |
| M3: OFDM + Android | End of Week 12 | OFDM mode + Android APK + visualizations |
| M4: CI/CD Complete | End of Week 16 | Automated builds, signed releases, deployment pipelines |
| M5: v1.0.0 Launch | End of Week 20 | Production release on Play Store, GitHub, Snap Store |

---

## 8. Risk Register

| Risk | Probability | Impact | Mitigation | Owner |
|---|---|---|---|---|
| Speaker/mic frequency response varies | High | Medium | AGC + adaptive calibration | DSP Team |
| Audio latency too high on Android | Medium | High | Use AAudio, profile early | DSP Team |
| OFDM fails in multipath | Medium | Medium | Use CSS fallback, add CP | DSP Team |
| App store rejection | Low | High | Clear permission rationale, privacy policy | Product Team |
| Cross-platform audio inconsistency | Medium | Medium | miniaudio abstraction, per-platform testing | DSP Team |
| C/C++ memory bugs | Medium | High | AddressSanitizer, fuzzing, bounds checking | DSP Team |

---

## 9. Dependencies

| Dependency | Type | Status | Impact if Delayed |
|---|---|---|---|
| Flutter 3.41 stable | External | Available | Blocks UI development |
| KissFFT | Vendored | Available | Blocks DSP core |
| miniaudio | Vendored | Available | Blocks audio I/O |
| Android NDK | External | Available | Blocks Android build |
| Play Store account | External | Required | Blocks Android deployment |
| Apple Developer account | External | Required | Blocks macOS signing |

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-07-18 | PxA Labs | Initial roadmap |
