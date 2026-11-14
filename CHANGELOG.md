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
- **ui:** Resolve padding named parameter typo and deprecation warnings in settings and dashboard
- **engine:** Make native FFI bindings lazy in TxEngine and RxEngine to prevent test environment crash
- **test:** Resolve Flutter widget and unit test errors including ServicesBinding initialization and finder ambiguity
- **ui:** Safely cache AppState in didChangeDependencies to prevent crash on monitor dispose
- **ui:** Inject mock AudioService in AppState to fix tests & prevent duplicate/failing CI workflows
- **test:** Inject MockAudioService in widget tests to prevent native plugin channel crashes
- **test:** Scroll ListView in dashboard_test to bring message log into view
- **ui:** Prevent notifyListeners calls after AppState is disposed
- **test:** Implement updateConfig in MockAudioService
- **ci:** Add Flutter platform projects and repair Build/Release workflows
- **ci:** Align CI Flutter with platform templates and upgrade record to v7
- **ci:** Install GStreamer for Linux and silence STL1011 on Windows builds
- **sync:** Normalised, energy-gated Schmidl-Cox metric for OFDM frame timing (#88)
- **ffi:** Send all frame bits and size modulator buffers by the API's overflow protocol (#88)
- **api,rs:** Validate sw_config_t at the FFI boundary; decode RS with explicit parity (#28)
- **sync:** Bounds-check CFO estimation, timing metric and matched filter (#28)
- **css:** Derive symbol length from the chirp template; remove debug print (#28)
- **ofdm:** Guard short inputs, unchecked allocations and failed frame writes (#28)
- **fec,packet:** Make FEC round-trip and enforce packet length limits (#28)
- **sync:** Zero-initialise analytic buffers in CFO estimator (#28)
- **ofdm:** Compute 1/SNR without dividing by zero for silent pilots (#28)
- **app:** Do not return a Future from setState in the storage card
- **android:** Import Properties in app build script
- **ci:** Gate Android signature check on apksigner exit status, not cert wording
- **ci:** Resolve libunwind conflict on ubuntu-22.04 desktop builds
- **linux:** Avoid SIGPIPE false failure when checking .deb contents
- **release:** Checksum and publish a flattened asset set
- **ci:** Pin Flutter 3.50.0 to avoid macOS AOT snapshotter crash
- **ci:** Pin Flutter 3.50.0 only for macOS desktop jobs
- **app:** Drop unused import after FileGateway switch
- **app:** Numeric-safe level semantics; test true 200% linear text scale
- **app:** Onboarding permission button follows the same platform switch as the gate
- **sync:** Double both parts of positive bins in analytic signal
- **ofdm:** Back off FFT window into CP and estimate CFO on it
- **docs:** Exclude dart doc markdown from nav check; re-sync BER sweep windows on sw_detect_frame offset
- **docs:** Track frame slots from a verified anchor in the BER sweep decoder
- **ofdm:** Confine OFDM to the configured ultrasonic band
- **ofdm:** Demodulate every symbol whose FFT window fits; drop padding workarounds
- **app:** Serialise settings writes and enable sample save on first audio
- **ofdm,cli:** Earliest matched-filter preamble; CLI demodulates from detected start
- **css:** Score preamble slots against the mean slot energy and the weaker down slot
- **css:** Explicit preamble slot bounds for static analysis; silence GCC stringop false positive
- **css:** Explicit window bound in sliding max for static analysis
- **tx:** Peak-normalize OFDM frames to cfg.amplitude and guard playback
- **ofdm:** Whiten the last symbol's padding to cut the frame crest factor
- **android:** Import Properties in app build script
- **ci:** Gate Android signature check on apksigner exit status, not cert wording
- **ci:** Pin macOS build to Flutter 3.50.0 to avoid 3.47 gen_snapshot crash
- **ci:** Pin macOS build to Flutter 3.50.0 to avoid 3.47 gen_snapshot crash
- **android:** Import Properties in app build script
- **ci:** Gate Android signature check on apksigner exit status, not cert wording
- **ci:** Pin macOS build to Flutter 3.50.0 to avoid 3.47 gen_snapshot crash
- **tx:** Deliver the first frame; size frames to the config; drop RX settle workaround
- **audio:** Create RecordAudioService plugins lazily; derive link test fragment counts from the frame budget

### Build

- Ignore AGENTS.md for local agent configuration
- **native:** ASan/UBSan/libFuzzer options and property-based fuzz harnesses (#28)

### CI

- Add GitHub Actions workflows (CI, Build, Release, Dependabot)
- Add auto-changelog with git-cliff
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting
- Retrigger workflows [skip ci]
- Retrigger workflows
- Add benchmarking, cross-platform matrix, coverage, static analysis, and PR linting
- Fix invalid GitHub action major versions in workflow files
- **workflow:** Add auto-formatting and auto-commit step to CI for Dart files
- Remove redundant auto-format and auto-commit steps in ci.yml
- Add sanitizer, libFuzzer and static-analysis jobs; document workflow (#28)
- **build:** Produce debug/split release APKs and AAB with packaged .so checks
- Temporary format diff job (to be removed)
- **docs:** Add MkDocs Material site with Doxygen and dart doc API builds (#37)
- Add coverage gates, quality dashboard and Linux integration test job
- Annotate coverage numbers and fix dashboard artifact paths
- List least-covered files and locate dashboard summaries
- Annotate uncovered line ranges for the least-covered files
- Enforce coverage thresholds and document the quality gates
- **build:** Produce debug/split release APKs and AAB with packaged .so checks
- **build:** Produce debug/split release APKs and AAB with packaged .so checks

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
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- **ci:** Document desktop packaging, signing secrets and dry-run releases
- **ci:** Note the macOS Flutter pin
- Document analytic signal, FFT window backoff and CFO/noise estimates
- Add site pages, verified C/Dart API reference and Signal Lab (#37)
- **testing:** Add field test and hardware profiling plans with BER sweep tool (#96, #98)
- **legal:** Draft privacy policy, terms of service and Play Store listing (#97)
- **readme:** Describe the real project structure, status and build steps
- **signal-chain:** OFDM transmit spectrum figures from test_ofdm_spectrum
- **css:** Document SF chirp symbols, sync, SF range and computed rates
- Update OFDM raw peaks and spectrum figures after padding whitening
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
- **ui:** Implement Dashboard, Signal Monitor, and Settings screens (#30)
- **ui:** Dynamic config settings propagation and OpenSSF secure bounds checks
- **ui:** Implement throughput meter, SNR display & connection status widget (#90)
- **engine:** Config-driven RX pipeline with shared frame codec for CSS and OFDM (#88)
- **settings:** Persist modem settings, add BPSK/QPSK selector, fix CP options (#88)
- **agc:** Native automatic gain control with FFI API (#92)
- **app:** Apply AGC in the RX pipeline with settings toggle and gain readout (#92)
- **link:** Payload fragmentation, file transfer and stop-and-wait ARQ (#89, #100)
- **app:** WAV recording, signal import/demodulation and message export (#33)
- **android:** Build libsoundwave.so with the NDK and use AAudio/OpenSL ES
- **app:** Request RECORD_AUDIO at runtime and load libsoundwave.so on Android
- **desktop:** Bundle libsoundwave and package Windows/macOS/Linux builds
- **release:** Sign, package and checksum desktop builds with dry-run mode
- **monitor:** Spectrum analyzer, waterfall and OFDM constellation widgets (#71, #91)
- **app:** Add WCAG AA light/dark themes, onboarding tutorial and accessibility pass (#93)
- **cli:** Adopt the app frame format; whiten OFDM data; verify preamble
- **css:** SF-bit LoRa-style chirp symbols with robust whole-buffer preamble sync
- **app:** CSS geometry from SF and bandwidth; remove dead CSS knobs
- **android:** Build libsoundwave.so with the NDK and use AAudio/OpenSL ES
- **app:** Request RECORD_AUDIO at runtime and load libsoundwave.so on Android
- **android:** Build libsoundwave.so with the NDK and use AAudio/OpenSL ES
- **app:** Request RECORD_AUDIO at runtime and load libsoundwave.so on Android

### Maintenance

- Change license from MIT to Apache 2.0
- Merge main into feat/ci-benchmarking
- Remove temporary format helper workflow
- Temporary format helper workflow
- Remove temporary format helper workflow
- Land stacked PRs #118, #120, #121 and #119 (#122)

### Performance

- **sync:** FFT overlap-save correlation for CSS sync; replay fuzz regressions in CTest (#28)

### Styling

- **app:** Run dart format on all app files
- **app:** Run dart format with SDK 3.6.0 on all files
- **ui:** Format Dart code with dart format
- **ui:** Format Dart code with dart format
- Remove trailing whitespace in dashboard_test.dart
- **ui:** Format audio_service.dart according to dart format guidelines
- **ui:** Apply standard dart format to audio_service.dart
- Apply dart format and fix analyzer warning
- Dart format test files; drop temporary format job
- **test:** Dart format
- Format rx_stream_start_test
- Format tx_engine_test
- Format link_engines_test

### Testing

- **qa:** Implement AWGN channel simulator and BER benchmarking harness (#72)
- **app:** Fix ProviderNotFound, CSV csv contains format, closeTo tolerance, and ServicesBinding in tests
- **native:** Real TX->audio->RX loopback tests, run in CI against this commit's DSP (#88)
- **native:** Memory-safety regression suite and ASan canaries (#28)
- **link:** Fix zone and capture-start races in link-layer tests
- **link:** Diagnostics for broadcast loopback
- **link:** Fix diagnostics string
- **link:** Format diagnostics
- **link:** Settle receivers on background noise before transfers
- **native:** Pad constellation test frames, report per-symbol EVM
- Bound constellation EVM by the measured clean-loopback level
- Check constellation decisions against frame bits; diagnose monitor peak
- Pad native constellation frames; pump monitor test past throttle
- **app:** Use isSemantics instead of deprecated containsSemantics
- **app:** Scroll settings controls fully into view before tapping
- **app:** Measure text scale on body text, not the clamped AppBar title
- **app:** Scroll to the OFDM card in the 200% text test
- Temporary OFDM EVM diagnostic (baseline)
- Bound noiseless OFDM loopback EVM below 1 %
- Remove temporary OFDM EVM diagnostic
- **docs:** Add verbose window logging to the BER sweep smoke test
- **app:** Load UI preferences before boot in integration test; fix coverage report dir
- **native:** Add packet/FEC and C API error-path tests
- **app:** AppState link-layer e2e, SharedPreferences store and status bar state tests
- **app:** File transfer progress card states
- **app:** Drop unnecessary import
- **native:** RS decoder stages, OFDM frame negotiation, CSS sync defaults, pilot SNR
- **app:** Message log actions save/cancel/failure flows
- Fix formatting and give CSS sync test a realistic capture length
- **app:** Settings controls drive AppState
- **app:** Offline decode on a background isolate with the real DSP
- **app:** FFI error codes surface as SwException
- **app:** Capture audio before building the log actions
- **app:** Drop unnecessary import
- **app:** Wait for async transfer progress and sequential prefs saves
- **app:** Reproduce lost same-tick settings saves and stale sample button
- **app:** Cross-decode app and soundwave-cli WAV files in CI
- **ofdm:** Band-aware config boundaries; zero-init FFT buffers; spectrum report in CI
- **css:** Adapt API/sync tests to SF symbols; full-preamble lag scoring at buffer end
- **css:** Cover argument, config and hostile-input edge cases; clamp narrowing casts
- **api:** CSS-only geometry check uses a band the OFDM plan accepts
- Reference spectrum/EVM checks to the TX frame gain; fix test ordering
- Reproduce first-frame playback drop and first-frame RX failures

### Merge

- WAV recording, signal import & message export (#33)
- Android NDK build, AAudio backend & APK/AAB CI (#87, #94)
- Android NDK branch into desktop pipeline (stack on #124)
- Desktop packaging & release pipeline (#95, #35)
- Spectrum analyzer, waterfall & constellation (#71, #91)
- Integrate origin/integration/overnight into fragmentation/ARQ branch
- Theme, onboarding & accessibility (#93)
- Integrate latest origin/integration/overnight (theme, onboarding, a11y)
- Fix OFDM analytic-signal/equalizer EVM
- Docs site, README, legal drafts & test plans (#37, #97, #96, #98)
- Coverage gates, quality dashboard & integration tests (#34, #36)
- Settings save race & sample button fixes
- Real spreading-factor CSS & robust CSS sync


