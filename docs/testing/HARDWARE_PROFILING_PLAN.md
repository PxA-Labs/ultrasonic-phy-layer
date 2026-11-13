# Hardware Profiling Plan: Latency, Startup, Memory, CPU

Covers issue #98. **No measurements exist yet.** This page describes how to make them. Results go into `docs/PERFORMANCE_BENCHMARKS.md`, which should be created only once real data exists (see [§8](#8-recording-results)).

## 1. Targets (from the PRD) and how each is defined here

| Metric | PRD target | Operational definition used in this plan |
|---|---|---|
| Audio latency | < 50 ms capture-to-output | (a) The **device audio path** round trip, measured with a loopback tool. (b) **Soundwave processing latency**: time from the end of a frame's audio at the receiver microphone to the message appearing on screen. See §3 |
| Startup | < 2 s cold launch | Time to the first rendered frame after a cold start (process not running) |
| Memory | < 120 MB RAM | Peak **PSS** (Android) or **resident/working set** (desktop) of the app process, with the Dart heap and native heap reported separately |
| CPU | < 15 % on a mid-range device | Mean process CPU over 60 s, reported **both** as % of one core and as % of all cores (the PRD does not say which) |

Messages take a long time on air (CSS default: about 6 s for even a 2-byte message, derived from the code), so "latency" must never be measured as send-to-receive time without subtracting the airtime.

## 2. Device and OS matrix

| Platform | Minimum the build actually supports | Devices to test |
|---|---|---|
| Android | `minSdk` = Flutter SDK default (check `aapt dump badging` on the APK). AAudio needs API 26+, and older versions use the OpenSL ES fallback | One mid-range phone (Pixel 5 class), one low-end phone, one API 26–28 device |
| Windows | MSIX `MinVersion` 10.0.17763 (Windows 10 1809) | Windows 10 and Windows 11, x64 |
| macOS | `MACOSX_DEPLOYMENT_TARGET` 12.0 | One Apple Silicon and one Intel Mac (the universal build) |
| Linux | Release built on Ubuntu 22.04 (glibc 2.35). **Ubuntu 20.04, which issue #98 lists, cannot run these binaries** | Ubuntu 22.04 and 24.04, x64, PulseAudio/PipeWire |

Plus three speaker/microphone hardware configurations: built-in, a USB audio interface, and a Bluetooth headset. A Bluetooth headset is expected to fail at ultrasonic frequencies because of codec band limits; record that as a result, not as an error.

Always use **release** or **profile** builds. Debug builds use the Dart JIT and are not representative.

## 3. Latency

### 3a. Device audio-path round trip (per platform)

| Platform | Tool / method |
|---|---|
| Android | Google **OboeTester** → *Round Trip Latency* with a loopback adapter (or acoustically, speaker to mic). Test both the AAudio and OpenSL ES APIs |
| Windows, macOS, Linux | A loopback cable from line-out to line-in (or an audio interface). Play an impulse and record it with any tool that timestamps playback and capture on the same clock (for example a DAW's latency measurement, or `jack_iodelay` on Linux with JACK) |

This measures the hardware and OS path that `libsoundwave` uses through miniaudio. It is not Soundwave-specific.

### 3b. Soundwave processing latency

The app has no built-in timestamps for this today. Method (no code changes needed):

1. Put the TX and RX devices side by side and film **both screens and the TX speaker** with a phone at 240 fps (or ≥ 60 fps).
2. Send a short message (pipeline B in the [field test plan](FIELD_TEST_PLAN.md)). Record the config.
3. From the video, measure t₀ (TX *Send* tap registered, button state change) and t₁ (message visible on RX).
4. Processing latency ≈ (t₁ − t₀) − frame airtime − TX scheduling time. Take the airtime from [Signal chain](../architecture/signal-chain.md) or `FrameGeometry`.
5. Repeat 10 times per config (CSS default, OFDM default).

The video gives no reference for the moment the frame actually ends, so this estimates the upper bound of RX processing to within ±1 video frame plus the uncertainty of the TX start. A more accurate method would add timestamps to `RxEngine` (frame end sample index → decode completion). That would be a code change, which this plan only recommends.

## 4. Startup time (cold)

| Platform | Command / method |
|---|---|
| Android | `adb shell am force-stop com.pxalabs.soundwave` then `adb shell am start -W -n com.pxalabs.soundwave/.MainActivity`. Record `TotalTime` (ms). Repeat 10 times and report the median and max. Optionally capture a Perfetto trace |
| All platforms | `flutter run --profile --trace-startup -d <device>` writes `build/start_up_info.json` (`timeToFirstFrameMicros`, `timeToFrameworkInitMicros`). Repeat 5 times |
| Windows/macOS/Linux (release package) | Reboot or drop caches (`sync; echo 3 \| sudo tee /proc/sys/vm/drop_caches` on Linux) for a true cold start. Measure launch to first window with a 240 fps video of the screen if no trace is available |

Report first launch (onboarding shown) and later launches (onboarding skipped) separately.

## 5. Memory

| Platform | Command |
|---|---|
| Android | `adb shell dumpsys meminfo com.pxalabs.soundwave`: record *TOTAL PSS*, *Native Heap*, *Dalvik Heap*, *Graphics*. Sample every 5 s with a loop and keep the peak |
| Windows | `Get-Process soundwave \| Select-Object WorkingSet64, PrivateMemorySize64`, sampled every 5 s |
| macOS | `footprint -p <pid>` or `vmmap --summary <pid>` (physical footprint) |
| Linux | `grep -E 'VmRSS\|VmHWM' /proc/<pid>/status` (VmHWM is the peak RSS) |
| Dart heap (all) | Flutter DevTools → *Memory* (profile build): peak Dart heap and external memory |

Native allocations to keep in mind: one-second capture and playback ring buffers, per-frame modulation buffers, KissFFT plans, and the 10 s rolling sample buffer (≈ 480k samples) used by *Save Signal Sample*.

## 6. CPU

| Platform | Command |
|---|---|
| Android | `adb shell top -H -d 1 -p <pid>` (per thread) or `adb shell dumpsys cpuinfo`. Perfetto for detail |
| Windows | `Get-Counter '\Process(soundwave)\% Processor Time' -SampleInterval 1 -MaxSamples 60` (the value is % of one core; divide by the core count for % of total) |
| macOS | `top -pid <pid> -l 60 -s 1 -stats cpu` |
| Linux | `pidstat -u -p <pid> 1 60` (sysstat) |

## 7. Scenarios (run each for 60 s after a 10 s settle)

| ID | Scenario | Metrics |
|---|---|---|
| S0 | Idle on the Dashboard, not listening | Memory, CPU |
| S1 | Listening, CSS default, no signal | Memory, CPU |
| S2 | Listening, CSS default, receiving a frame (TX on another device) | Memory peak, CPU |
| S3 | Listening, OFDM default, receiving frames every 1 s | Memory peak, CPU |
| S4 | S3 with the Monitor tab open (spectrum + waterfall + constellation) | Memory, CPU, and UI jank (DevTools frame chart) |
| S5 | Transmitting a 1 KiB file with ARQ on (OFDM) | Memory, CPU |
| S6 | WAV recording for 5 min while listening | Memory growth (should be flat; the recorder streams to disk) |
| S7 | Import and decode a 60 s WAV | Peak memory, wall time |

## 8. Recording results

Create `docs/PERFORMANCE_BENCHMARKS.md` only when data exists. Include:

- device, OS version, build SHA, build mode, and power state (plugged in, battery saver off);
- one table per metric: rows are platform × scenario; columns are median, max, number of runs, target, and PASS/FAIL;
- the raw logs (command output) in an archive or a linked folder;
- for any FAIL, a linked issue with profiling evidence (trace or DevTools capture).

The DSP micro-benchmarks in `native/benchmarks/` (`benchmark.yml`) measure isolated kernels on CI runners. They are **not** device measurements and must not be put into these tables.
