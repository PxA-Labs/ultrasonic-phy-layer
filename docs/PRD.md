# Product Requirements Document (PRD)

**Project:** Soundwave — Ultrasonic Physical Layer
**Version:** 1.0
**Date:** July 18, 2026
**Author:** PxA Labs (Archit Mittal, Purvansh Joshi)

---

## 1. Executive Summary

Soundwave is a cross-platform application that enables short-range, device-to-device digital communication using ultrasonic audio waves (18–22 kHz). It maps digital bitstreams into high-frequency acoustic signals via consumer speakers and decodes them on the receiving side using microphones. The product targets Android (APK) and desktop platforms (Windows, macOS, Linux).

---

## 2. Problem Statement

Current short-range wireless communication (Bluetooth, NFC) requires pairing, has protocol overhead, and is subject to frequency congestion. Ultrasonic communication offers a **zero-infrastructure, pairing-free alternative** for proximity-based data exchange using existing hardware (speakers and microphones) that every device already has.

---

## 3. Target Users

| Segment | Use Case |
|---|---|
| **Developers & Researchers** | Experiment with acoustic PHY protocols, test chirp/OFDM modulation |
| **Security-Conscious Users** | Pairing-free, line-of-sight data exchange that is inherently hard to intercept remotely |
| **IoT Integrators** | Device discovery and bootstrap in environments where RF is restricted |
| **General Consumers** | Share small payloads (URLs, contacts, text) between nearby devices |

---

## 4. Product Goals

| Goal | Metric | Target |
|---|---|---|
| Cross-platform reach | Supported platforms | Android 8+, Windows 10+, macOS 12+, Ubuntu 20.04+ |
| Usable range | Max distance at 80 dB SPL | ≥ 5 meters (20 kHz) |
| Data throughput | Raw bit rate (OFDM mode) | ≥ 1 kbps |
| Reliability | Bit Error Rate (BER) | < 10⁻⁵ at 10 dB SNR |
| Latency | End-to-end encode→decode | < 200 ms |
| Inaudibility | Frequency band | 18–22 kHz (above adult hearing threshold) |
| App size | Installed size | < 50 MB |

---

## 5. Functional Requirements

### 5.1 Modulation & Encoding

| ID | Requirement | Priority |
|---|---|---|
| F-01 | Support Chirp Spread Spectrum (CSS) modulation | P0 |
| F-02 | Support OFDM modulation with BPSK/QPSK mapping | P0 |
| F-03 | Reed-Solomon forward error correction (configurable RS(n,k)) | P0 |
| F-04 | CRC-32 frame integrity verification | P0 |
| F-05 | Configurable carrier frequency (18–22 kHz) | P1 |
| F-06 | Configurable symbol rate and bandwidth | P1 |

### 5.2 Synchronization & Detection

| ID | Requirement | Priority |
|---|---|---|
| F-07 | Preamble detection via matched filtering (CSS) | P0 |
| F-08 | Zadoff-Chu sequence-based frame sync (OFDM) | P0 |
| F-09 | Carrier frequency offset (CFO) estimation via Schmidl-Cox | P0 |
| F-10 | Automatic gain control (AGC) | P1 |

### 5.3 Audio I/O

| ID | Requirement | Priority |
|---|---|---|
| F-11 | Real-time microphone input capture | P0 |
| F-12 | Real-time speaker output generation | P0 |
| F-13 | Platform-native audio backends (AAudio, CoreAudio, WASAPI, ALSA) | P0 |
| F-14 | Configurable sample rate (44.1 kHz default) | P1 |
| F-15 | Low-latency pull-mode audio processing | P0 |

### 5.4 User Interface

| ID | Requirement | Priority |
|---|---|---|
| F-16 | Real-time spectrum analyzer / waterfall plot | P1 |
| F-17 | Constellation diagram for modulation visualization | P2 |
| F-18 | Connection status and throughput display | P0 |
| F-19 | Settings panel (frequency, modulation, FEC, gain) | P0 |
| F-20 | Dark/light theme support | P2 |

### 5.5 Data Handling

| ID | Requirement | Priority |
|---|---|---|
| F-21 | Send text payloads up to 4 KB | P0 |
| F-22 | Send binary file payloads up to 1 MB | P1 |
| F-23 | Payload fragmentation and reassembly | P1 |
| F-24 | Automatic retransmission on CRC failure | P2 |

---

## 6. Non-Functional Requirements

| Category | Requirement | Target |
|---|---|---|
| **Performance** | CPU usage during active transmission | < 15% on mid-range devices |
| **Performance** | Memory footprint | < 120 MB RAM |
| **Latency** | Audio capture to output pipeline | < 10 ms |
| **Reliability** | Crash-free rate | ≥ 99.5% |
| **Accessibility** | Screen reader compatibility | WCAG 2.1 AA |
| **Security** | No network permissions required | Air-gapped operation |
| **Privacy** | No data collection or telemetry | Zero telemetry by default |
| **Compliance** | Audio output limits | ≤ 80 dB SPL at 1 meter |

---

## 7. Platform Requirements

| Platform | Minimum OS | Audio Backend | Distribution |
|---|---|---|---|
| Android | Android 8.0 (API 26) | AAudio (OpenSL ES fallback) | APK / Play Store |
| Windows | Windows 10 (1903+) | WASAPI | EXE / MSIX / Microsoft Store |
| macOS | macOS 12 Monterey | CoreAudio | DMG / Notarized |
| Linux | Ubuntu 20.04+ | ALSA / PulseAudio / PipeWire | DEB / AppImage / Snap |

---

## 8. Success Metrics

| Metric | Measurement Method | Target |
|---|---|---|
| End-to-end throughput | File transfer benchmark | ≥ 1 kbps (OFDM), ≥ 100 bps (CSS) |
| BER vs SNR | Controlled noise test | < 10⁻⁵ at 10 dB SNR |
| Range | Outdoor line-of-sight test | ≥ 5 m at 20 kHz |
| Startup time | Cold launch measurement | < 2 seconds |
| App store rating | User reviews | ≥ 4.0 stars |

---

## 9. Release Criteria

- [ ] All P0 functional requirements implemented and tested
- [ ] BER < 10⁻⁵ at 10 dB SNR validated in lab conditions
- [ ] APK built, signed, and installable on Android 8+ devices
- [ ] Desktop builds (Windows, macOS, Linux) pass smoke tests
- [ ] CI/CD pipeline green on all platforms
- [ ] Privacy policy and terms of service published
- [ ] README and user documentation complete

---

## 10. Out of Scope (v1.0)

- Real-time voice/audio streaming over ultrasonic channel
- Multi-device mesh networking
- iOS support (planned for v2.0)
- Web browser support
- Encryption / secure payload transfer (planned for v2.0)
- Adaptive modulation based on channel conditions

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Speaker/microphone frequency response varies across devices | Reduced range/throughput | AGC + adaptive power control + device calibration |
| Ambient noise in 18–22 kHz band | Increased BER | CSS mode for noisy environments + FEC |
| Doppler from device motion | Synchronization loss | Doppler-tolerant CSS mode + pilot-aided OFDM equalization |
| Platform audio API differences | Inconsistent latency | miniaudio abstraction layer with platform-specific backends |
| App store rejection (audio permissions) | Delayed launch | Clear permission rationale in store listing |

---

## 12. Appendix

### References
- MATHEMATICAL_MODEL.md — Complete PHY layer equations
- [cyrinx](https://github.com/serjshevchenko/cyrinx) — Reference ultrasonic OFDM implementation (36–39 kbps)
- [sonance](https://github.com/nickoala/sonance) — Robust ultrasonic communication (2–16 kbps)

### Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-07-18 | PxA Labs | Initial PRD |
