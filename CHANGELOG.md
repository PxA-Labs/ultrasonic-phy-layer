# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Bug Fixes

- **ci:** Skip Flutter/CMake steps when project files don't exist yet
- **ci:** Repair changelog workflow download and extraction
- **ci:** Replace manual download with official git-cliff action
- **ci:** Resolve git-cliff URL via GitHub API instead of pinned action
- **ci:** Remove invalid sort_commits value in cliff.toml
- **ci:** Replace job-level hashFiles with step-level checks to fix CI parsing
- Macos missing stdlib.h, msvc __attribute__ guard, lint-pr permissions, remove dep-review
- Ci triggers and workflow stability
- Conditional -lm for non-Windows, missing stdlib.h in test_css_demodulate
- Add missing stdlib.h in test_cfo/ofdm_modulate/ofdm_demodulate, pass --config Release for MSVC multi-config generator
- Export DLL symbols on Windows via SW_BUILD_DLL compile definition
- Build static lib on Windows to avoid DLL symbol export issues
- Lcov coverage — use --ignore-errors for missing gcda files, fix path
- Remove over-broad lcov exclude patterns that stripped all records
- Replace broken action-semantic-pull-request with inline validation script
- **tests:** Handle SW_ERR_NOT_IMPLEMENTED gracefully in test_e2e
- **ci:** Fix benchmark timer dereference and guard build workflow
- **ci:** Link kiss_fft in benchmarks, update release artifacts to v4, and add step guards
- **ci:** Update benchmark link library target to kissfft
- **ci:** Format benchmark JSON output with value and unit for github-action-benchmark
- **ci:** Disable auto-push in benchmark workflow until gh-pages exists
- **ci:** Add skip-fetch-gh-pages to benchmark workflow
- **ci:** Set save-data-file to false in benchmark workflow
- **ci:** Add skip-fetch-gh-pages alongside save-data-file in benchmark workflow
- **ci:** Add fetch-depth 0 to checkout in benchmark workflow
- **cmake:** Resolve Windows library names and coverage linking flags (#15)
- **ci:** Update artifact action version in release workflow (#15)
- **native:** Address code review feedback for native scaffolding (#51)
- **native:** Enable global compile and link options for coverage and sanitizers
- **dsp-core:** Rename kissfft to kiss_fft target in benchmark CMake (#76)
- **ofdm:** Resolve PR #78 review comments on OFDM modulator and FFI boundaries
- **ofdm:** Resolve PR #79 review comments on memory safety and API consistency
- **app:** Resolve static analysis warnings and undefined type errors in Flutter project

### Build

- Ignore AGENTS.md for local agent configuration

### CI

- Add GitHub Actions workflows (CI, Build, Release, Dependabot)
- Add auto-changelog with git-cliff
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting
- Retrigger workflows [skip ci]
- Retrigger workflows
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting
- Fix invalid GitHub action major versions in workflow files

### Documentation

- Update MIT License and add mathematical model of physical layer
- Upgrade README with badges, acoustic channel data insights, and math models
- Add core developers and project organization
- Add production documents (PRD, tech stack, CI/CD, roadmap)
- Move MATHEMATICAL_MODEL.md to docs/ and update README links
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Add SECURITY.md (#45)
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Remove emojis from README headings (#47)
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Add AGENTS.md workflow guidelines (#17)
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- **onboarding:** Add developer guide, API reference, PR template, and Doxygen headers (#73)
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]

### Features

- Add project skeleton for native C DSP library and Flutter app
- Professional CI/CD pipeline with cross-platform matrix, benchmarks, coverage, and static analysis (#46)
- **crc:** Implement CRC-32 IEEE 802.3 append, verify, and comprehensive unit tests (#16)
- **rs:** Implement GF(2^8) arithmetic and Reed-Solomon systematic encoder (#17)
- **repo:** Add CODEOWNERS file for @archittmittal and @purvanshjoshi
- **dsp-core:** Setup native project scaffolding and CMake build system (#15)
- **dsp-core:** Implement Reed-Solomon decoder (BMA, Chien, Forney) (#18) (#67)
- **dsp-core:** Implement LFM chirp generation & CSS modulation (#19) (#75)
- **css:** Implement CSS demodulator and sync pipelines (#24)
- **ofdm:** Implement OFDM subcarrier mapping, IDFT and cyclic prefix (#20)
- **ofdm:** Implement OFDM demodulation, channel estimation, and equalization (#23)
- **sync:** Implement CSS and OFDM timing synchronization and noise estimation (#21)
- **api:** Implement miniaudio I/O ring buffers and FFI API bindings (#25, #26)
- **dsp:** Implement SIMD NEON and AVX2 vectorization for core DSP loops (#69)
- **app:** Implement FFI bindings and Audio Service layer (#29) (#31)
- **app:** Implement TX/RX Engine, Message Queue, History persistence and unit tests (#32)
- **app:** Implement TX/RX Engine, Message Queue, History persistence and unit tests (#32)
- **ci:** Correct working directory for Flutter builds (#36)
- **cli:** Implement standalone developer CLI tool soundwave-cli (#70)

### Maintenance

- Change license from MIT to Apache 2.0
- Merge main into feat/ci-benchmarking

### Styling

- **app:** Run dart format on all app files
- **app:** Run dart format with SDK 3.6.0 on all files

### Testing

- **qa:** Implement AWGN channel simulator and BER benchmarking harness (#72)
- **app:** Fix ProviderNotFound, CSV csv contains format, closeTo tolerance, and ServicesBinding in tests


