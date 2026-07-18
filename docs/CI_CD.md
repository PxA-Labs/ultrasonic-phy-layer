# CI/CD Pipeline Specification

**Project:** Soundwave — Ultrasonic Physical Layer
**Version:** 1.0
**Date:** July 18, 2026
**Author:** PxA Labs (Archit Mittal, Purvansh Joshi)

---

## 1. Overview

This document specifies the Continuous Integration and Continuous Deployment pipeline for the Soundwave project using **GitHub Actions**. The pipeline covers quality gates, multi-platform builds, signing, testing, and deployment.

---

## 2. Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions Pipeline                   │
│                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │  PR / Push   │──>│  Quality     │──>│  Build       │    │
│  │  Trigger     │   │  Gate        │   │  Matrix      │    │
│  └──────────────┘   └──────────────┘   └──────┬───────┘    │
│                         │                      │             │
│                    ┌────┴────┐          ┌──────┴───────┐    │
│                    │ analyze │          │ Android APK  │    │
│                    │ test    │          │ Windows EXE  │    │
│                    │ format  │          │ macOS DMG    │    │
│                    │ lint    │          │ Linux DEB    │    │
│                    └─────────┘          └──────┬───────┘    │
│                                                 │             │
│                                        ┌────────┴────────┐  │
│                                        │   Sign & Deploy  │  │
│                                        │  - Play Store    │  │
│                                        │  - GitHub Release│  │
│                                        │  - Snap Store    │  │
│                                        │  - MS Store      │  │
│                                        └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Workflow Files

### 3.1 Quality Gate — `.github/workflows/ci.yml`

**Trigger:** Push to any branch, Pull Requests to `main`

```yaml
name: CI

on:
  push:
    branches: ['*']
  pull_request:
    branches: [main]

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.x'
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze Dart code
        run: flutter analyze --fatal-infos

      - name: Check formatting
        run: dart format --set-exit-if-changed .

      - name: Run Flutter tests
        run: flutter test --coverage

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: coverage/lcov.info

      - name: Build DSP core (C/C++)
        run: |
          cd native
          cmake -B build -DCMAKE_BUILD_TYPE=Release
          cmake --build build

      - name: Run DSP core tests
        run: |
          cd native/build
          ctest --output-on-failure
```

### 3.2 Build Matrix — `.github/workflows/build.yml`

**Trigger:** Push to `main`, version tags (`v*`)

```yaml
name: Build

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.x'
          cache: true
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - name: Build APK
        run: flutter build apk --release
      - name: Build AAB
        run: flutter build appbundle --release
      - uses: actions/upload-artifact@v4
        with:
          name: android-release
          path: |
            build/app/outputs/flutter-apk/app-release.apk
            build/app/outputs/bundle/release/app-release.aab

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.x'
          cache: true
      - name: Build Windows
        run: flutter build windows --release
      - uses: actions/upload-artifact@v4
        with:
          name: windows-release
          path: build/windows/x64/runner/Release/

  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.x'
          cache: true
      - name: Build macOS
        run: flutter build macos --release
      - uses: actions/upload-artifact@v4
        with:
          name: macos-release
          path: build/macos/Build/Products/Release/

  build-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.x'
          cache: true
      - name: Install Linux dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config \
            libgtk-3-dev liblzma-dev libstdc++-12-dev
      - name: Build Linux
        run: flutter build linux --release
      - uses: actions/upload-artifact@v4
        with:
          name: linux-release
          path: build/linux/x64/release/bundle/
```

### 3.3 Sign & Deploy — `.github/workflows/release.yml`

**Trigger:** Version tags (`v*`)

```yaml
name: Release

on:
  push:
    tags: ['v*']

jobs:
  deploy-android:
    needs: [build-android]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: android-release
      - name: Decode keystore
        run: echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > keystore.jks
      - name: Deploy to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT }}
          packageName: com.pxalabs.soundwave
          releaseFiles: app-release.aab
          track: internal
          status: completed

  deploy-github-release:
    needs: [build-android, build-windows, build-macos, build-linux]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            android-release/*
            windows-release/*
            macos-release/*
            linux-release/*
          draft: true
          generate_release_notes: true

  deploy-snap:
    needs: [build-linux]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: linux-release
          path: snap/gui/
      - uses: snapcore/action-build@v1
        id: snapcraft
      - uses: snapcore/action-publish@v1
        env:
          SNAPCRAFT_STORE_CREDENTIALS: ${{ secrets.SNAP_TOKEN }}
        with:
          snap: ${{ steps.snapcraft.outputs.snap }}
          release: stable
```

---

## 4. Required Secrets

| Secret | Platform | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Android | Base64-encoded JKS keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Android | Keystore password |
| `ANDROID_KEY_ALIAS` | Android | Key alias |
| `ANDROID_KEY_PASSWORD` | Android | Key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Android | Play Store API credentials |
| `MACOS_CERTIFICATE_BASE64` | macOS | P12 signing certificate |
| `MACOS_P12_PASSWORD` | macOS | P12 certificate password |
| `MACOS_CODESIGN_IDENTITY` | macOS | codesign identity string |
| `MACOS_NOTARIZATION_APPLE_ID` | macOS | Apple ID for notarization |
| `MACOS_NOTARIZATION_PASSWORD` | macOS | App-specific password |
| `MACOS_NOTARIZATION_TEAM_ID` | macOS | Apple Developer Team ID |
| `WINDOWS_CERT_PFX_BASE64` | Windows | PFX code signing certificate |
| `WINDOWS_CERT_PASSWORD` | Windows | PFX password |
| `SNAP_TOKEN` | Linux | Snapcraft store token |
| `CODECOV_TOKEN` | All | Codecov upload token |

---

## 5. Caching Strategy

| Cache | Key | Path | Restored When |
|---|---|---|---|
| Flutter pub | `pubspec.lock` hash | `~/.pub-cache` | Any Flutter step |
| Gradle | `*.gradle*` hash | `~/.gradle/caches` | Android build |
| CMake | `native/**` hash | `native/build/` | DSP core build |
| Xcode | Derived data hash | `~/Library/Developer/Xcode/DerivedData` | macOS build |

---

## 6. Testing Strategy

### 6.1 Unit Tests

| Layer | Framework | Coverage |
|---|---|---|
| Dart/Flutter | `flutter_test` | UI logic, models, bridge layer |
| C/C++ DSP core | CTest + Catch2 | Encoder, modulator, synchronizer, demodulator |
| FFI bindings | `flutter_test` with mock C library | Dart ↔ C interface |

### 6.2 Integration Tests

| Test | Tool | Scope |
|---|---|---|
| Audio loopback | `flutter integration_test` | Speaker → Mic pipeline |
| Cross-module | `flutter integration_test` | Encode → Modulate → Transmit → Receive → Decode |

### 6.3 Performance Tests

| Metric | Method | Threshold |
|---|---|---|
| FFT latency | Benchmark harness | < 1 ms per 1024-point FFT |
| End-to-end latency | Timestamp markers | < 200 ms |
| Memory usage | Profiler | < 120 MB |
| CPU usage | Profiler | < 15% during active TX |

### 6.4 Golden Vector Tests

| Test | Input | Expected | Validation |
|---|---|---|---|
| OFDM IDFT | Known symbols | Known time-domain signal | Bit-exact match |
| Chirp generation | Known parameters | Known waveform | MSE < 1e-6 |
| RS encode | Known data block | Known codeword | Bit-exact match |
| CRC-32 | Known payload | Known checksum | Bit-exact match |

---

## 7. Branch Strategy

```
main (production)
├── develop (integration)
│   ├── feature/css-modulator
│   ├── feature/ofdm-demodulator
│   ├── feature/android-audio
│   └── feature/spectrum-analyzer
├── release/v1.0.0
└── hotfix/urgent-fix
```

| Branch | Purpose | CI Trigger | Deploy |
|---|---|---|---|
| `main` | Production-ready code | Full pipeline | Release workflow |
| `develop` | Integration branch | Quality gate + build | No |
| `feature/*` | Feature development | Quality gate | No |
| `release/*` | Release candidates | Full pipeline | Staging |
| `hotfix/*` | Urgent fixes | Full pipeline | Production |

---

## 8. Deployment Targets

| Platform | Channel | Trigger | Automation |
|---|---|---|---|
| Android (Play Store) | Internal → Beta → Production | Tag `v*` | `r0adkll/upload-google-play` |
| Windows | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| macOS | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| Linux (Snap) | Snap Store (stable) | Tag `v*` | `snapcore/action-publish` |
| Linux (DEB) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| Linux (AppImage) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |

---

## 9. Release Process

1. Update `VERSION` in `pubspec.yaml` and `native/CMakeLists.txt`
2. Update `CHANGELOG.md` with release notes
3. Create PR from `develop` → `main`
4. After merge, create git tag: `git tag v1.0.0`
5. Push tag: `git push origin v1.0.0`
6. GitHub Actions triggers release workflow
7. Artifacts built, signed, and deployed to all targets
8. Publish GitHub Release (mark as latest)

---

## 10. Monitoring & Alerts

| Item | Tool | Alert |
|---|---|---|
| CI failures | GitHub Actions | Email + Slack notification |
| Test coverage drop | Codecov | PR comment + status check |
| Dependency vulnerabilities | Dependabot | Auto-PR + alert |
| Build size increase | Custom script | PR comment (warn if >10% increase) |

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-07-18 | PxA Labs | Initial CI/CD specification |
