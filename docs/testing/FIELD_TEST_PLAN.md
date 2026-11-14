# Field Test Plan: BER/FER vs Distance, Multipath and Doppler

Covers issue #96. **No field results exist yet.** This document is the procedure. Results go into `docs/BER_FIELD_TEST_RESULTS.md`, which should be created only once real measurements have been made (template in [§9](#9-recording-results)).

## 1. Objectives and acceptance criteria

| # | Question | PRD target | How it is decided |
|---|---|---|---|
| O1 | Error rate at the reference SNR | BER < 10⁻⁵ at 10 dB SNR (CSS and OFDM) | §6.4 statistics; definitions in §2 |
| O2 | Usable range | ≥ 5 m in at least one environment | FER ≤ 1 % (**proposed**) at the distance, CSS default config |
| O3 | Multipath robustness | (none) | FER per environment at 1 m and 3 m |
| O4 | Doppler tolerance | (none) | FER at ±1 m/s compared with the static result at the same distance |
| O5 | Stability | (none) | FER drift over 1 h, interference cases |

!!! warning "Two definitions the team must agree on before testing"
    1. **"BER" in the PRD.** `soundwave-cli` only reports frames that pass RS + CRC-32, so post-FEC residual BER is effectively always 0. The measurable quantities are **FER** (frame error rate), **residual BER** on delivered frames, and **RS symbols corrected** (a lower bound on the pre-FEC byte error rate). Proposal: judge O1 by *residual BER including lost frames*. Count every lost frame as a failure, and require **0 lost frames and 0 bit errors over ≥ 3 × 10⁵ payload bits** (95 % confidence that BER < 10⁻⁵, rule of three). Measuring raw channel BER would need a new CLI option that dumps pre-FEC bits; that option does not exist.
    2. **"SNR".** The CLI prints an SNR *estimate* from preamble detection (`sw_detect_frame`). It is uncalibrated and its definition is specific to the implementation. Record it, but also record the **acoustic** quantities (signal SPL and noise floor at the receiver, §5.3). Do not report a "10 dB SNR" point unless it was measured with a stated method.

## 2. Metrics

| Metric | Definition | Source |
|---|---|---|
| FER | frames not delivered ÷ frames sent | `ber_sweep.py decode` → `summary.json` |
| Residual BER | bit errors in delivered payloads ÷ delivered payload bits (95 % upper bound 3/n when 0 errors) | same |
| RS correction rate | RS symbols corrected ÷ (delivered frames × codeword bytes) | same |
| CLI SNR estimate | median of `snr = … dB` printed by `soundwave-cli demodulate` | same |
| Signal level | SPL at the receiver microphone position during a frame, dB(Z) | Sound level meter |
| Noise floor | SPL with the transmitter silent, dB(Z), plus a 30 s WAV recording | Sound level meter + recording |
| Delay spread (optional) | RT60 of the room as a proxy (§5.4) | RT60 app/meter |

## 3. Two test pipelines

The app and `soundwave-cli` use the **same frame format** and modem defaults (see [Architecture](../architecture/overview.md#frame-formats)), so a recording from either pipeline can be decoded by either tool as long as the settings match.

| | **Pipeline A: CLI playback, offline decode** (primary) | **Pipeline B: app to app** (end-to-end check) |
|---|---|---|
| TX | Any device plays `playlist.wav` from `ber_sweep.py generate` (media player, or a laptop with a speaker) | Soundwave app, *Send* |
| RX | Any recorder at 44.1 kHz, 16-bit or 32-bit float, mono or stereo, **with audio processing off** (or the app's Record button, which records unprocessed through miniaudio) | Soundwave app, listening |
| Decode | `ber_sweep.py decode` (wraps `soundwave-cli demodulate`) | Live, in the app |
| Output | Per-frame CSV + summary JSON | Exported message log (JSON) with SNR per message |
| Strength | Repeatable: the same recording can be re-decoded after DSP changes | Exercises the real app stack, AGC and link layer |

Phone voice-memo apps often apply AGC, noise suppression and low-pass filtering that remove the 17–22 kHz band. Use a recorder with an "unprocessed" or "raw" mode, or the Soundwave app's own recorder.

## 4. Equipment

| Item | Requirement | Why |
|---|---|---|
| Device pair(s) | At least two different phone models, plus one laptop. Record model, OS version and app build (git SHA) | Speaker/mic response dominates performance |
| Sound level meter | IEC 61672 Class 1 or 2, **Z or C weighting**, documented response up to ≥ 20 kHz | A-weighting removes most energy at 18–21 kHz. Many meters roll off above 12.5 kHz, so record the meter model and its rated range |
| Tape measure, 2 stands/tripods | Devices at 1.0 m height, centre to centre | Repeatable geometry |
| Protractor or angle template | 0°, 45°, 90°, 180° | Speaker and mic directivity |
| Thermometer / hygrometer | ±1 °C, ±5 % RH | Air absorption at ultrasonic frequencies depends on both (ISO 9613-1) |
| Laptop with `soundwave-cli` and Python 3 | Built from the same commit as the app | Generate and decode |
| Doppler rig (optional) | Trolley or slider on a ≥ 4 m straight track, a metronome, a stopwatch or video at ≥ 60 fps | 1 m/s motion |
| Interference sources | Bluetooth speaker with a fixed music track and a speech track | Stress tests |

## 5. Setup and calibration

### 5.1 Build and generate the test signals

```bash
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release -DSW_BUILD_TESTS=OFF
cmake --build native/build --target soundwave_cli
export SOUNDWAVE_CLI=$PWD/native/build/soundwave-cli

# CSS default config: 20 frames x 64 B (~16.5 s/frame), 1 s gaps
python3 docs/testing/ber_sweep.py generate --mode css --frames 20 --payload-bytes 64 \
  --gap 1.0 --lead-in 2.0 --verify --out runs/css64
# OFDM default config (N=256, CP=64, QPSK, ZF): 200 frames x 64 B, 0.3 s gaps
python3 docs/testing/ber_sweep.py generate --mode ofdm --frames 200 --payload-bytes 64 \
  --gap 0.3 --lead-in 2.0 --verify --out runs/ofdm64
# Offline baseline (SIMULATED, AWGN): run before going into the field
python3 docs/testing/ber_sweep.py simulate --manifest runs/css64/manifest.json --snr 0,3,6,10,20
```

`--verify` decodes every clean frame once, so a broken build is caught before any field time is spent. Keep `manifest.json` with the recordings, because decoding needs it.

### 5.2 Transmit level

1. Put the sound level meter at 1.0 m on the transmitter axis.
2. Play `playlist.wav` (or send a long CSS message from the app) and read the maximum level, dB(Z), **during a frame**.
3. Adjust the device volume until it reads **≤ 80 dB(Z) SPL at 1 m** (PRD compliance limit). Record the volume step and the reading.
4. Never exceed this level, and never hold a transmitting device near anyone's ears.

### 5.3 Noise floor and signal level at the receiver

At every test position:

1. Measure SPL with the transmitter silent for 30 s (L<sub>Zeq</sub>), and record 30 s of WAV on the receiver.
2. Measure SPL during a frame.
3. Write down temperature and relative humidity.

### 5.4 Room characterization (multipath)

The repo has no impulse-response tool. As a proxy, measure RT60 (any room-acoustics app or meter that uses interrupted noise or impulse methods) and describe the surfaces. Each recording of `playlist.wav` is saved, so a delay-spread analysis can be added later without repeating the measurement.

## 6. Test matrix

### 6.1 Configurations

| ID | Mode | Parameters | Raw rate (derived) |
|---|---|---|---|
| C1 | CSS | f₀ 19 kHz, B 2 kHz, T 20 ms (default) | 50 bit/s |
| C2 | CSS | f₀ 18 kHz, B 1 kHz, T 50 ms (*Long Range* preset) | 20 bit/s |
| O1 | OFDM | N 256, CP 64, QPSK, ZF (default) | 22.9 kbit/s |
| O2 | OFDM | N 256, CP 64, QPSK, MMSE | 22.9 kbit/s |
| O3 | OFDM | N 256, CP 64, BPSK, MMSE | 11.4 kbit/s |

`soundwave-cli` exposes `--freq`, `--bw`, `--fft`, `--cp`, `--amp` and `--equalizer`. It has **no options** for chirp duration T or BPSK. C2 and O3 can therefore only be run through pipeline B (app to app) until the CLI gains those options.

### 6.2 Distance (line of sight, 0°, devices at 1.0 m height)

| Environment | Distances (m) | Configs |
|---|---|---|
| E1: quietest available room (furnished bedroom or studio) | 0.5, 1, 2, 3 | C1, O1, O2 |
| E2: office (normal HVAC, no speech) | 1, 3, 5 | C1, C2, O1, O2 |
| E3: large room or hall | 1, 3, 5, 8 | C1, C2, O1 |

### 6.3 Angle, multipath and Doppler

| Test | Positions | Configs |
|---|---|---|
| Angle | 1 m and 3 m at 0°, 45°, 90°, 180° (receiver behind the transmitter) | C1, O1 |
| Reverberant room (kitchen/bathroom, hard surfaces) | 1 m, 3 m | C1, O1, O2 |
| Corner (TX facing a corner 0.5 m away, RX 2 m behind) | fixed | C1, O1 |
| Absorptive room (soft furnishings) | 1 m, 3 m | C1, O1 |
| Doppler: TX moving at 1 m/s **toward** the RX, from 4 m to 1 m | 5 runs | C1, O1 |
| Doppler: TX moving at 1 m/s **away**, from 1 m to 4 m | 5 runs | C1, O1 |

At 1 m/s a 4 m track gives 3 s of motion per pass. That covers OFDM frames (≈ 50 ms each) but not one CSS frame (≈ 16.5 s at 64 B). For CSS, use 12 B payloads (≈ 8.2 s/frame, still longer than one pass) and treat the CSS Doppler result as **qualitative only**, or run a back-and-forth track for the full frame and log the motion profile.

### 6.4 How many frames (statistics)

| Goal | Required observation | 64 B payload frames | CSS C1 airtime | OFDM O1 airtime |
|---|---|---|---|---|
| Screening FER to about ±10 % | 20 frames | 20 | ≈ 6 min | ≈ 7 s |
| "10,000-bit sequence" (issue #96) | 10,000 payload bits | 20 | ≈ 6 min | ≈ 7 s |
| Residual BER < 10⁻⁵ at 95 % confidence (O1) | 3 × 10⁵ error-free payload bits, 0 lost frames | 586 | **≈ 2.9 h** | ≈ 3.4 min |

Airtime is derived from the code and includes the generator's gaps (1 s for CSS, 0.3 s for OFDM). A 10,000-bit run can only support a residual-BER claim down to about 3 × 10⁻⁴. Run the full O1 sample only at the reference point (E2, 3 m), and use 20-frame screening runs everywhere else.

### 6.5 Stress

| Test | Procedure | Config |
|---|---|---|
| Long run | 1 h continuous playlist at E2, 3 m. Log device temperature at start and end | O1 (and C1 if time allows) |
| Music | Bluetooth speaker 1 m from the RX playing the fixed music track at 60 and 70 dB(Z) at the RX position | C1, O1 |
| Speech | Same, with the speech track | C1, O1 |
| Second ultrasonic source | A second transmitter 2 m away playing a different playlist at the same level, starting at random times | C1, O1 |

## 7. Procedure for one test point (pipeline A)

1. Place the devices, measure the distance and angle, and photograph the setup.
2. Record the environment data and the noise floor (§5.3).
3. Start recording on the receiver (44.1 kHz).
4. Play `playlist.wav` on the transmitter at the calibrated volume.
5. Stop recording 2 s after the playlist ends. Name the file `<testid>_<config>_<env>_<dist>m_<angle>deg_<rxdevice>.wav`, for example `T014_O1_E2_3m_0deg_pixel7.wav`.
6. Decode:

```bash
python3 docs/testing/ber_sweep.py decode --manifest runs/ofdm64/manifest.json \
  --recording T014_O1_E2_3m_0deg_pixel7.wav --label T014 --out results/T014
```

7. Copy the `summary.json` values into the results table (§9). Archive the WAV, `frames.csv` and `summary.json`.

For **pipeline B**, send a fixed list of 20 numbered messages (`T014-01` … `T014-20`) from the app, export the receiver's message log as JSON, and count the messages received. FER = missing ÷ 20. SNR comes from the log.

## 8. Recording conditions to log for every point

Test ID, date and time, operator, TX device (model, OS, volume step), RX device (model, OS, recorder app and its processing setting), app/CLI git SHA, config ID, environment ID and description, distance, angle, height, temperature, RH, noise floor dB(Z), signal dB(Z), RT60 (if measured), frames sent and delivered, FER, residual bit errors, payload bits, RS corrections, median CLI SNR, and notes.

## 9. Recording results

Create `docs/BER_FIELD_TEST_RESULTS.md` only when data exists, with:

1. The environment and equipment list (models, meter class and frequency range).
2. One CSV-style table per test group, with the columns from §8.
3. Plots (FER vs distance per config). Generate them from the CSVs and commit the script that made them.
4. A PASS/FAIL table against §1. Every number must point to an archived recording or result file.
5. A **Limitations** section (device count, meter bandwidth, SNR definition).

Never mix simulated (`ber_sweep.py simulate`, CI) numbers into these tables. If they are shown for comparison, label them **SIMULATED**.

## 10. Safety

Keep the transmit level ≤ 80 dB(Z) at 1 m. Tell people in the area before testing, keep pets out of the test room, and stop if anyone reports discomfort. OFDM mode is clearly audible on the current build.
