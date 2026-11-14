# Signal chain & parameters

This page lists what the modulators **actually generate** on the current code, and the band, rate and airtime numbers that follow from it.

!!! info "How to read the numbers"
    - **Derived** values are computed from the formulas in `native/src/css/css_modulate.c`, `native/src/ofdm/ofdm_modulate.c` and `soundwave_app/lib/engine/frame_geometry.dart`. They are exact for the code, but they are not measurements.
    - **Simulated** values come from CI tests that add white Gaussian noise in software.
    - **Measured over the air**: none yet. See the [field test plan](../testing/FIELD_TEST_PLAN.md).
    - **Targets** come from the [PRD](../PRD.md) and are goals, not results.

## CSS (chirp) mode

**Implementation (derived from code).** `sw_css_modulate` sends one bit per chirp. Bit `0` is an up-chirp and bit `1` is a down-chirp, MSB first. Every frame starts with a preamble of 8 up-chirps followed by 2 down-chirps. A chirp of duration $T$ and amplitude $A$ is

$$s(t) = A\cos\!\left(2\pi\left(f_0 + \tfrac{B}{2T}t\right)t\right),\qquad 0 \le t < T,$$

with $B>0$ for an up-chirp ($f_0 \to f_0+B$) and $B<0$ for a down-chirp ($f_0 \to f_0-|B|$). The configured `carrier_freq` is the **start** frequency $f_0$, not the centre. The signal therefore spans $[f_0-B,\ f_0+B]$.

The `sf` (spreading factor) field is validated (6..12) but is **not used** by the `sw_css_modulate` / `sw_css_demodulate` path. Only `symbol_duration`, `carrier_freq`, `bandwidth`, `amplitude` and `sample_rate` affect the waveform.

| Configuration | $f_0$ / $B$ / $T$ | Occupied band | Samples per chirp (44.1 kHz) | Raw bit rate |
|---|---|---|---|---|
| Default (app and CLI) | 19 kHz / 2 kHz / 20 ms | 17–21 kHz | 882 | 50 bit/s |
| App preset *Long Range* | 18 kHz / 1 kHz / 50 ms | 17–19 kHz | 2205 | 20 bit/s |

Airtime (derived) for the app frame format (`CRC 4 B + payload + RS 32 B`, plus the 10-chirp preamble):

| Payload | Frame bytes | Default (20 ms) | Long Range (50 ms) |
|---|---|---|---|
| 2 B | 38 | 6.3 s | 15.7 s |
| 219 B (maximum) | 255 | 41.0 s | 102.5 s |

Note that the 17–18 kHz part of the default band is audible to many people.

## OFDM mode

**Implementation (derived from code).** `sw_ofdm_modulate` builds a **real-valued** OFDM signal with an $N$-point IFFT and Hermitian symmetry. Data and pilot subcarriers are placed **only inside the configured band** $[f_c - B/2,\ f_c + B/2]$ (`carrier_freq` ± `bandwidth`/2; default 19 kHz ± 1 kHz = **18–20 kHz**). See [Mathematical model §2.2.3](../MATHEMATICAL_MODEL.md#223-ultrasonic-band-plan).

- Subcarrier spacing: $\Delta f = f_s / N$.
- Active bins $k_{lo} = \lceil (f_c - B/2) N / f_s \rceil + 1$ to $k_{hi} = \lfloor (f_c + B/2) N / f_s \rfloor - 1$: one empty guard bin inside each band edge. DC, the audible range, the Nyquist bin and their mirrors stay empty on TX and RX.
- Rejected configurations (`SW_ERR_BAD_PARAM`): band reaching DC, band edge closer than $\Delta f$ to Nyquist, fewer than 4 active bins.
- Every 8th active bin (starting with the first) is a pilot (+1, −1, …). The rest carry BPSK (1 bit) or QPSK (2 bits). Data bits are whitened with PRBS15 so repeated payload bytes never produce identical symbols. Pilots track the common phase of each data symbol.
- Preamble: two identical Zadoff-Chu OFDM symbols (root 1) on the active bins, joined phase-continuously. They are used for timing (Schmidl-Cox, then phase-slope fine timing), CFO, the channel estimate and the noise estimate.
- Each symbol has a cyclic prefix of `cp_length` samples (C default $N/8$ when 0; the app and CLI default is 64). Its first $\lfloor N_{cp}/2\rfloor$ samples carry a raised-cosine cross-fade with the previous symbol; the frame ends with a $\lfloor N_{cp}/2\rfloor$-sample fade-out.

| $N$ / CP, band | $\Delta f$ | Active / pilot / data bins | Subcarrier centres | Symbol (incl. CP) | Raw rate BPSK / QPSK | Max app frame (255 B, QPSK) |
|---|---|---|---|---|---|---|
| 256 / 64, 18–20 kHz (default) | 172.3 Hz | 10 / 2 / 8 | 18.26–19.81 kHz | 320 samples (7.26 ms) | 1.10 / 2.21 kbit/s | 944 ms |
| 256 / 32, 18–20 kHz | 172.3 Hz | 10 / 2 / 8 | 18.26–19.81 kHz | 288 (6.53 ms) | 1.23 / 2.45 kbit/s | 849 ms |
| 512 / 64, 18–20 kHz | 86.1 Hz | 22 / 3 / 19 | 18.09–19.90 kHz | 576 (13.06 ms) | 1.45 / 2.91 kbit/s | 732 ms |
| 1024 / 128, 18–20 kHz | 43.1 Hz | 45 / 6 / 39 | 18.04–19.94 kHz | 1152 (26.12 ms) | 1.49 / 2.99 kbit/s | 759 ms |
| 2048 / 128, 18–20 kHz | 21.5 Hz | 91 / 12 / 79 | 18.02–19.96 kHz | 2176 (49.34 ms) | 1.60 / 3.20 kbit/s | 742 ms |
| 2048 / 128, 18–21 kHz (*High Speed* preset) | 21.5 Hz | 138 / 18 / 120 | 18.02–20.97 kHz | 2176 (49.34 ms) | 2.43 / 4.86 kbit/s | 544 ms |

All values are **computed** from the code at $f_s$ = 44.1 kHz (not measured). Raw rates are data bits per symbol over the symbol time, before CRC, RS parity and preamble overhead. The rate scales with the band: about $2B \cdot \tfrac{7}{8} \cdot \tfrac{N}{N+N_{cp}}$ bit/s for QPSK, minus the guard bins. The app's settings screen shows the same computed band and rate for the current configuration.

**Transmit spectrum (simulated, `native/tests/test_ofdm_spectrum.c`).** Periodogram of a 46-byte frame (CRC + 10-byte payload + RS parity), QPSK. The test requires ≥ 98.5 % of the energy inside the configured band and ≤ −40 dB below 16 kHz. The ~1 % outside the band is the main lobe of the outermost subcarriers, within a few hundred hertz of the band edges.

| $N$ / CP, band | Energy in band | Energy below 16 kHz | Energy below 17 kHz | Peak sample |
|---|---|---|---|---|
| 256 / 32, 18–20 kHz | 98.69 % | −44.7 dB | −33.8 dB | 1.11 |
| 256 / 64, 18–20 kHz (default) | 98.99 % | −53.9 dB | −44.4 dB | 1.11 |
| 512 / 64, 18–20 kHz | 99.17 % | −46.5 dB | −42.1 dB | 1.06 |
| 1024 / 128, 18–20 kHz | 99.20 % | −42.3 dB | −39.2 dB | 1.10 |
| 2048 / 128, 18–20 kHz | 99.49 % | −47.8 dB | −44.4 dB | 2.16 |
| 256 / 64, 18–21 kHz | 99.39 % | −43.0 dB | −39.2 dB | 1.41 |
| 2048 / 128, 18–21 kHz (*High Speed*) | 99.40 % | −56.2 dB | −49.9 dB | 2.47 |

Before this change the OFDM modulator ignored `carrier_freq` and `bandwidth` and spread energy over 5.7–21.9 kHz (N = 256): only about 11–15 % of the energy fell in 18–20 kHz and about −2 dB (≈ 60 %) was below 16 kHz (pure-Python model of the old modulator, same frame; peak samples 7–19).

The modulator output is not normalised: the peak values above exceed full scale for N = 2048, and the app plays the samples unscaled (`soundwave-cli` rescales to 0.8 before writing a WAV).

!!! warning "Not measured over the air"
    The band plan and spectrum are exact properties of the transmitted samples. Whether a given speaker and microphone pass 18–20 kHz, and what SNR they achieve there, has not been measured; see the [field test plan](../testing/FIELD_TEST_PLAN.md). Many devices roll off above 18–20 kHz, which is why the default band stops at 20 kHz.

## Receiver chain (both modes)

1. **AGC** (optional, app default on): target RMS 0.25, attack 1 ms, release 100 ms, gain range −20 to +32 dB ([math §6](../MATHEMATICAL_MODEL.md#6-automatic-gain-control-agc)).
2. **Frame detection** (`sw_detect_frame`): CSS uses a matched filter on the 8-up/2-down preamble pattern. OFDM uses the Schmidl-Cox metric on the repeated ZC preamble, refines it from the preamble's phase slope, and checks it against the known preamble (matched-filter fallback).
3. **CFO**: Schmidl-Cox on the two repeated preamble symbols (OFDM), computed on the analytic signal.
4. **OFDM only**: the FFT window backs off $\lfloor N_{cp}/4\rfloor$ samples into the CP (after the transmit cross-fade). Then a least-squares channel estimate from the preamble, a noise-variance estimate, per-symbol pilot phase correction, ZF or MMSE equalization, and de-whitening.
5. **Demapping** to bits, then in the app `FrameCodec.decode`: RS(255,223) decoding (up to 16 byte errors) and CRC-32 verification.

## What has been verified, and how

| Claim | Evidence | Kind |
|---|---|---|
| CSS and OFDM loopback decode correctly | `native/tests/test_e2e.c`, `integration_loopback.c`, Flutter `test/native/loopback_test.dart` | Simulation (digital loopback) |
| CSS BER < 10⁻³ for SNR ≥ 3 dB; OFDM BER < 10⁻² for SNR ≥ 10 dB | `native/tests/test_ber.c` assertions (8-byte payloads, AWGN over the whole frame) | Simulation |
| Noiseless OFDM loopback EVM < 1 % | `native/tests/test_constellation.c` | Simulation |
| AGC settles within ±0.11 dB for inputs −30 to +10 dB around target | `native/tests/test_agc.c` | Simulation |
| BER < 10⁻⁵ at 10 dB SNR, range ≥ 5 m | [PRD](../PRD.md) | **Target, not yet tested** |
| Audio latency < 50 ms, startup < 2 s, memory < 120 MB, CPU < 15 % | [PRD](../PRD.md) | **Target, not yet tested**; see [profiling plan](../testing/HARDWARE_PROFILING_PLAN.md) |

Atmospheric absorption in this band grows roughly with the square of frequency. The standard model is ISO 9613-1 (*Acoustics — Attenuation of sound during propagation outdoors — Part 1: Calculation of the absorption of sound by the atmosphere*). The project has not yet published any absorption or range figures that were checked against that standard or against measurement.
