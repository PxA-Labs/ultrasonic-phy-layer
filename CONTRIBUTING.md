# Contributing to Soundwave

First off, thank you for considering contributing to **Soundwave**! Soundwave is an open-source ultrasonic physical layer (PHY) library bringing cross-platform acoustic data transmission to desktop, mobile, and web applications.

---

## Code of Conduct & Contribution Philosophy

- **Authenticity & Excellence**: Write clean, self-documented, high-performance C11 and Dart code.
- **No Masking of Symptoms**: Never bypass failed assertions or swallow exceptions silently. Fix underlying root causes.
- **Empirical Verification**: Always run native tests (`ctest`) and Flutter unit tests before submitting a Pull Request.

---

## How to Get Started

### 1. Find or Open an Issue
- Check open issues with the [`good first issue`](https://github.com/PxA-Labs/ultrasonic-phy-layer/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first-issue%22) label.
- If proposing a new feature or architectural change, open a [GitHub Discussion](https://github.com/PxA-Labs/ultrasonic-phy-layer/discussions) first.

### 2. Local Environment Setup

#### Native C/C++ DSP Core
```bash
# Clone repository
git clone https://github.com/PxA-Labs/ultrasonic-phy-layer.git
cd ultrasonic-phy-layer

# Create build directory & configure CMake
mkdir -p build && cd build
cmake ../native -DCMAKE_BUILD_TYPE=Debug

# Compile native library and run CTest suite
cmake --build . --parallel
ctest --output-on-failure
```

#### Flutter Host Application
```bash
cd soundwave_app
flutter pub get
dart run ffigen            # Regenerate FFI bindings if soundwave_api.h changed
flutter test               # Run Flutter unit and widget tests
flutter run -d macos       # Run desktop app (macos, linux, or windows)
```

---

## Git Workflow & Branch Naming

- **Branch Naming**: Use descriptive branch names prefixed by topic:
  - `feat/rs-decoder-issue-18`
  - `fix/cfo-estimation-issue-22`
  - `docs/onboarding-guide-issue-73`
- **Conventional Commits**: Format commit messages as `type(scope): summary`:
  - `feat(dsp-core): implement Reed-Solomon decoder (BMA, Chien, Forney) (#18)`
  - `fix(cmake): resolve Windows library names and coverage linking flags (#15)`
  - `docs(onboarding): add developer guide and API reference (#73)`

---

## Pull Request Guidelines

Before submitting a Pull Request:

1. **Verify CTest**: All 17+ native test targets MUST pass cleanly (`ctest --output-on-failure`).
2. **Verify Memory Safety**: If modifying C code, test with AddressSanitizer (`cmake -DSW_USE_SANITIZER=ON ../native && ctest`). Zero leaks or undefined behaviors permitted.
3. **Flutter Formatting & Lints**: Run `flutter analyze` and `dart format .` inside `soundwave_app/`.
4. **Fill PR Template**: Ensure the PR description explains the motivation, implementation highlights, and empirical verification results.

---

## Reporting Bugs

When reporting an issue, please include:
- Operating system version (e.g., macOS 14.5 ARM64, Ubuntu 24.04 x86_64, Windows 11).
- Native compiler details (`clang --version` or `gcc --version`).
- Exact error log output or crash backtrace.
- Steps to reproduce.
