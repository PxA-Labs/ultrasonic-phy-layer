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
          flutter-version: '3.47.x'
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
          flutter-version: '3.47.x'
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
          flutter-version: '3.47.x'
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
          flutter-version: '3.47.x'
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
          flutter-version: '3.47.x'
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

**Triggers:**

- Tag push `v*` — full release: build, sign (when secrets exist), checksum, publish a **draft** GitHub Release, upload to stores.
- `workflow_dispatch` with input `dry_run` (default `true`) — builds, packages, signs-if-possible and checksums everything, uploading results **only as workflow artifacts**. No GitHub Release, store upload or tag is created. A non-dry manual run publishes only when dispatched on a `v*` tag ref.

  ```bash
  gh workflow run release.yml --ref <branch> -f dry_run=true
  ```

The `meta` job resolves the version (`v1.2.3` tag → `1.2.3`; otherwise `<pubspec version>-dryrun.<run number>`) and a `publish` flag that every publishing job checks.

#### Native library bundling

`libsoundwave` (from `native/`) ships inside every desktop app, and `lib/native/soundwave_native.dart` resolves it relative to the executable (`Platform.resolvedExecutable`):

| Platform | How it is built | Location in the app | Loader path |
|---|---|---|---|
| Windows | `ExternalProject` in `soundwave_app/windows/CMakeLists.txt` (part of `flutter build windows`) | `soundwave.dll` next to `soundwave.exe` (renamed from CMake's `libsoundwave.dll`) | `<exe dir>\soundwave.dll` |
| Linux | `ExternalProject` in `soundwave_app/linux/CMakeLists.txt` (part of `flutter build linux`) | `bundle/lib/libsoundwave.so` | `<exe dir>/lib/libsoundwave.so` |
| macOS | `soundwave_app/macos/packaging/embed_native.sh` after `flutter build macos` (universal arm64 + x86_64, install name `@rpath/libsoundwave.dylib`) | `soundwave.app/Contents/Frameworks/libsoundwave.dylib` | `<exe dir>/../Frameworks/libsoundwave.dylib` |

The `native/` project is built as an `ExternalProject` (not `add_subdirectory`) because its object-library target is also named `soundwave`, which clashes with the runner executable. Both `build.yml` and `release.yml` assert after the build that the library is present in the bundle, exports `sw_*` symbols and can be loaded (`ctypes.CDLL`), and that the macOS runner has the `@executable_path/../Frameworks` rpath and `NSMicrophoneUsageDescription`.

#### Desktop packages

| Platform | Runner | Artifacts | Packaging script |
|---|---|---|---|
| Windows | `windows-latest` | `soundwave-<ver>-windows-x64.zip`, `soundwave-<ver>-windows-x64.msix` | `soundwave_app/windows/packaging/package.ps1` (`Compress-Archive`, Windows SDK `makeappx`; manifest `AppxManifest.xml.in` declares `runFullTrust` + `microphone`) |
| macOS | `macos-latest` | `soundwave-<ver>-macos-universal.dmg` | `soundwave_app/macos/packaging/sign_and_package.sh` (`codesign` with hardened runtime + `Runner/Release.entitlements`, `hdiutil` UDZO, `notarytool` + `stapler`) |
| Linux | `ubuntu-22.04` (glibc 2.35 baseline) | `soundwave-<ver>-linux-x64.tar.gz`, `soundwave_<ver>_amd64.deb`, `Soundwave-<ver>-x86_64.AppImage` | `soundwave_app/linux/packaging/package.sh` (`tar`, `dpkg-deb` installing to `/opt/soundwave` + `/usr/bin/soundwave`, `appimagetool` 1.9.1) |
| All | `ubuntu-latest` (`checksums` job) | `SHA256SUMS`, `SHA256SUMS.asc` (when GPG key set) | inline |

`build.yml` produces the same desktop packages unsigned (macOS ad-hoc signed) on every `main` push / app PR, so packaging regressions surface before a tag.

macOS microphone access: `Info.plist` has `NSMicrophoneUsageDescription`; `Release.entitlements` (applied when signing) has `com.apple.security.app-sandbox` and `com.apple.security.device.audio-input`. The packaging script fails if the signed app lacks the audio-input entitlement.

#### Signing (all optional; gated on secret presence)

`secrets` cannot be used in step-level `if:`, so each job exposes a presence flag in job-level `env` (e.g. `HAS_WINDOWS_CERT: ${{ secrets.WINDOWS_CERTIFICATE_BASE64 != '' }}`) and signing steps test that flag. Without secrets the pipeline still succeeds with unsigned packages.

| Platform | When secrets exist | Without secrets |
|---|---|---|
| Windows | `signtool` (SHA-256, DigiCert RFC 3161 timestamp) signs `soundwave.exe`, `soundwave.dll` and the MSIX. MSIX `Publisher` comes from repository variable `MSIX_PUBLISHER` and must equal the certificate subject. | Unsigned zip + unsigned MSIX (MSIX installs only after signing / developer mode sideload). |
| macOS | Certificate imported into a temporary keychain; frameworks/dylibs then the app are signed with `Developer ID Application` + hardened runtime + timestamp; DMG signed, notarized with `xcrun notarytool submit --wait` and stapled. Keychain deleted afterwards. | Ad-hoc signature (`codesign -s -`), not notarized; Gatekeeper will require right-click → Open. |
| Linux | `SHA256SUMS` detached-signed (`SHA256SUMS.asc`) with the GPG key and verified. | Unsigned `SHA256SUMS`. |

#### Publishing

- `checksums` flattens all platform artifacts into one `release-assets` artifact plus `SHA256SUMS`; `deploy-github-release` (needs every platform build + `checksums`, and `publish == 'true'`) creates a **draft** release from exactly that set.
- `deploy-android` (Play Store internal track) and the Snap publish step also require `publish == 'true'`.
- Snap packaging runs only once `snap/snapcraft.yaml` exists (not yet added).

---

## 4. Required Secrets

All signing/publishing secrets are optional: when one is missing the corresponding step is skipped with a `::notice::` and unsigned packages are produced. Add them under *Settings → Secrets and variables → Actions*.

| Secret | Platform | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Android | Base64-encoded JKS keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Android | Keystore password |
| `ANDROID_KEY_ALIAS` | Android | Key alias |
| `ANDROID_KEY_PASSWORD` | Android | Key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Android | Play Store API credentials |
| `MACOS_CERTIFICATE_BASE64` | macOS | Base64 of the **Developer ID Application** certificate + private key exported as `.p12` (`base64 -i cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | macOS | Password of that `.p12` |
| `MACOS_NOTARIZATION_APPLE_ID` | macOS | Apple ID email used for `notarytool` |
| `MACOS_NOTARIZATION_TEAM_ID` | macOS | Apple Developer Team ID |
| `MACOS_NOTARIZATION_APP_PASSWORD` | macOS | App-specific password for that Apple ID |
| `WINDOWS_CERTIFICATE_BASE64` | Windows | Base64 of the code-signing `.pfx` (`[Convert]::ToBase64String([IO.File]::ReadAllBytes('cert.pfx'))`) |
| `WINDOWS_CERTIFICATE_PASSWORD` | Windows | Password of that `.pfx` |
| `LINUX_GPG_PRIVATE_KEY` | Linux / all | ASCII-armored private key (`gpg --armor --export-secret-keys <id>`) used to sign `SHA256SUMS` |
| `LINUX_GPG_PASSPHRASE` | Linux / all | Passphrase of that key (empty if none) |
| `SNAP_TOKEN` | Linux | Snapcraft store token |
| `CODECOV_TOKEN` | All | Codecov upload token |

| Repository **variable** (not secret) | Purpose |
|---|---|
| `MSIX_PUBLISHER` | MSIX `Identity/@Publisher`; must exactly equal the Windows certificate subject (e.g. `CN=PxA Labs, O=PxA Labs, C=IN`). Defaults to `CN=PxA Labs`. |

The macOS certificate is detected by the `Developer ID Application` identity in the `.p12`; notarization runs only when that identity and all three `MACOS_NOTARIZATION_*` secrets are present.

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
| Windows (zip, MSIX) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| macOS (DMG) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| Linux (Snap) | Snap Store (stable) | Tag `v*` | `snapcore/action-publish` |
| Linux (tar.gz, DEB, AppImage) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |
| Checksums (`SHA256SUMS[.asc]`) | GitHub Releases | Tag `v*` | `softprops/action-gh-release` |

---

## 9. Release Process

1. Update `VERSION` in `pubspec.yaml` and `native/CMakeLists.txt`
2. Update `CHANGELOG.md` with release notes
3. Create PR from `develop` → `main`
4. Rehearse with a dry run: `gh workflow run release.yml --ref main -f dry_run=true`; check the uploaded artifacts and `SHA256SUMS`
5. After merge, create git tag: `git tag v1.0.0`
6. Push tag: `git push origin v1.0.0`
7. GitHub Actions triggers release workflow
8. Artifacts built, signed, and deployed to all targets
9. Review and publish the draft GitHub Release (mark as latest)

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
| 1.1 | 2026-11-14 | PxA Labs | Desktop packaging, native-library bundling, signing, dry-run releases, checksums (#95, #35) |
