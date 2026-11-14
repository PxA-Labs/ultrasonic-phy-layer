# Build from source

This page covers the native C core, the `soundwave-cli` tool, the Flutter app on each platform, and the documentation site. The commands match the CI workflows (`.github/workflows/ci.yml`, `build.yml`, `release.yml`, `docs.yml`). If this page and a workflow disagree, the workflow is what CI actually runs.

## Prerequisites

| Component | Requirement | Used by CI |
|---|---|---|
| Native core | CMake ≥ 3.20, a C11 compiler (GCC, Clang, AppleClang or MSVC) and a C++ compiler (only for the Catch2 test runner) | `ubuntu-latest`, `macos-latest`, `windows-latest` |
| Flutter app | Flutter 3.47.x stable (macOS release jobs pin 3.50.0, see [CI/CD](../CI_CD.md)) | `subosito/flutter-action@v2` |
| Android | Android SDK + NDK + CMake 3.22+ (Gradle installs them on demand), JDK 17 | `build.yml` → `build-android` |
| Linux desktop | GTK 3 development headers and the usual Flutter Linux dependencies (`clang`, `ninja-build`, `pkg-config`, `libgtk-3-dev`) | `build.yml` |
| Docs site | Python 3.10+, `pip install -r docs/requirements.txt`; optionally Doxygen and the Flutter SDK for the API pages | `docs.yml` |

All third-party C code is vendored in `native/vendor/` (KissFFT, miniaudio), so there are no submodules to fetch.

## 1. Native core and tests

```bash
git clone https://github.com/PxA-Labs/ultrasonic-phy-layer.git
cd ultrasonic-phy-layer/native
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
ctest --test-dir build --output-on-failure --build-config Release
```

This builds `libsoundwave` (static and shared), the test executables (`test_crc`, `test_rs_decoder`, `test_ofdm_demodulate`, `test_ber`, `test_e2e`, ... and the Catch2 runner `catch_tests`), the fuzz smoke tests (`fuzz_*_smoke`), and `soundwave-cli`.

Useful CMake options (see `native/CMakeLists.txt`):

| Option | Default | Effect |
|---|---|---|
| `SW_BUILD_TESTS` | `ON` | Unit/integration tests and CTest registration |
| `SW_BUILD_BENCHMARKS` | `OFF` | Micro-benchmarks in `native/benchmarks/` |
| `SW_BUILD_COVERAGE` | `OFF` | gcov/lcov instrumentation |
| `SW_ENABLE_ASAN` / `SW_ENABLE_UBSAN` | `OFF` | Sanitizers |
| `SW_ENABLE_FUZZER` | `OFF` | libFuzzer harnesses (LLVM Clang) |
| `SW_FUZZ_SMOKE` | `ON` | Fuzz harnesses as CTest smoke tests |

Presets are available too: `cmake --preset release` (also `default`, `debug`, `asan`, `ubsan`, `fuzz`). Sanitizers and fuzzing are covered in the [developer guide](../DEVELOPER_GUIDE.md#sanitizers--fuzzing).

## 2. soundwave-cli

`soundwave-cli` is built with the core on every host platform (it is skipped for Android):

```bash
cmake --build native/build --target soundwave_cli
./native/build/soundwave-cli modulate --mode css --input "Hello" --output hello.wav
./native/build/soundwave-cli demodulate --mode css --input hello.wav
```

See the [CLI guide](../CLI_GUIDE.md).

## 3. Flutter app

The app loads `libsoundwave` at run time through `dart:ffi`. How the library gets next to the app depends on the platform.

=== "Linux"

    ```bash
    cd soundwave_app
    flutter pub get
    flutter run -d linux            # debug
    flutter build linux --release   # bundle in build/linux/x64/release/bundle/
    ```

    `soundwave_app/linux/CMakeLists.txt` builds `native/` as an `ExternalProject` and installs `libsoundwave.so` into `bundle/lib/`. Packaging (`.tar.gz`, `.deb`, AppImage) is done by `soundwave_app/linux/packaging/package.sh`.

=== "Windows"

    ```powershell
    cd soundwave_app
    flutter pub get
    flutter run -d windows
    flutter build windows --release
    ```

    `soundwave_app/windows/CMakeLists.txt` builds `native/` and copies it next to `soundwave.exe` as `soundwave.dll`. `windows/packaging/package.ps1` creates the zip and MSIX.

=== "macOS"

    ```bash
    cd soundwave_app
    flutter pub get
    flutter build macos --release
    ./macos/packaging/embed_native.sh   # builds a universal libsoundwave.dylib into Contents/Frameworks
    ```

    For `flutter run -d macos` during development, build the library first (`cmake -S native -B native/build && cmake --build native/build --target soundwave_shared`). The app also searches `../native/build/`.

=== "Android"

    ```bash
    cd soundwave_app
    flutter build apk --debug
    flutter build apk --release --split-per-abi
    flutter build appbundle --release
    ```

    Gradle's `externalNativeBuild` compiles `native/CMakeLists.txt` with the NDK for `arm64-v8a`, `armeabi-v7a` and `x86_64`. Audio uses miniaudio's AAudio backend (API 26+) with an OpenSL ES fallback. Release signing reads `android/key.properties`; without it, release builds are debug-signed. Details are in the [developer guide](../DEVELOPER_GUIDE.md#android-ndk--aaudio).

iOS is not set up: there is no `ios/` directory.

### Running the Flutter tests

```bash
cmake -S native -B native/build-ffi -DCMAKE_BUILD_TYPE=Release -DSW_BUILD_TESTS=OFF
cmake --build native/build-ffi --target soundwave_shared
cd soundwave_app
SOUNDWAVE_LIB=$PWD/../native/build-ffi/libsoundwave.so flutter test
```

Without a loadable library, the real-DSP loopback tests in `test/native/` are skipped. CI sets `SOUNDWAVE_REQUIRE_NATIVE=1` so that a missing library fails the run instead.

## 4. Documentation site

```bash
pip install -r docs/requirements.txt
doxygen docs/api/Doxyfile                                # optional: C API HTML
(cd soundwave_app && flutter pub get && dart doc --output ../docs/api/dart .)   # optional: Dart API HTML
mkdocs serve
```

`mkdocs build --strict` fails on any broken link or anchor. The [C API](../API_REFERENCE.md) and [Dart API](../api/dart-api.md) pages link to the generated HTML, so a strict build needs both generators to run first, as the `docs.yml` workflow does. The site is deployed to GitHub Pages only from `main`.
