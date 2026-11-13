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

**Implementation (derived from code).** `sw_ofdm_modulate` builds a **real-valued baseband** OFDM signal with an $N$-point IFFT and Hermitian symmetry. The `carrier_freq` and `bandwidth` fields are **not used** by the OFDM modulator: the band is fixed by $N$ and the sample rate.

- Subcarrier spacing: $\Delta f = f_s / N$.
- Active bins $k = N/8 + 1 \ldots N/2 - 1$. DC, a guard of $N/8$ bins and the Nyquist bin stay empty.
- Every 8th active bin (starting with the first) is a pilot. The rest carry BPSK (1 bit) or QPSK (2 bits).
- Preamble: two identical Zadoff-Chu OFDM symbols (root 1) on all active bins. They are used for timing, CFO (Schmidl-Cox), the channel estimate and the noise estimate (see [Mathematical model](../MATHEMATICAL_MODEL.md#4-demodulation--channel-equalization)).
- Each symbol is followed by a cyclic prefix of `cp_length` samples (C default $N/8$ when 0; the app and CLI default is 64).

| $N$ / CP | $\Delta f$ | Active / pilot / data bins | Occupied band | Symbol (incl. CP) | Raw rate BPSK / QPSK | Max app frame (255 B, QPSK) |
|---|---|---|---|---|---|---|
| 256 / 64 (default) | 172.3 Hz | 95 / 12 / 83 | 5.7–21.9 kHz | 320 samples (7.26 ms) | 11.4 / 22.9 kbit/s | 109 ms |
| 512 / 64 | 86.1 Hz | 191 / 24 / 167 | 5.6–22.0 kHz | 576 (13.06 ms) | 12.8 / 25.6 kbit/s | 118 ms |
| 1024 / 128 | 43.1 Hz | 383 / 48 / 335 | 5.6–22.0 kHz | 1152 (26.12 ms) | 12.8 / 25.6 kbit/s | 157 ms |
| 2048 / 128 (*High Speed* preset) | 21.5 Hz | 767 / 96 / 671 | 5.5–22.0 kHz | 2176 (49.34 ms) | 13.6 / 27.2 kbit/s | 197 ms |

All values are at $f_s$ = 44.1 kHz. Raw rates are PHY symbol rates before CRC, RS parity and preamble overhead.

!!! warning "OFDM is not ultrasonic on this code base"
    With this subcarrier placement, OFDM energy covers roughly 5.5–22 kHz, which is well inside the audible range. The raw rates above also assume an ideal channel. Typical consumer speakers and microphones roll off strongly above about 18 kHz, so the upper subcarriers may not survive a real acoustic channel at all. Moving OFDM into a narrow high band (for example by restricting active bins to the 18–21 kHz region) would cut the raw rate in proportion to the bins kept. This page documents the current behavior and does not propose a design.

## Receiver chain (both modes)

1. **AGC** (optional, app default on): target RMS 0.25, attack 1 ms, release 100 ms, gain range −20 to +32 dB ([math §6](../MATHEMATICAL_MODEL.md#6-automatic-gain-control-agc)).
2. **Frame detection** (`sw_detect_frame`): CSS uses a matched filter on the 8-up/2-down preamble pattern. OFDM uses the repeated ZC preamble.
3. **CFO**: Schmidl-Cox on the two repeated preamble symbols (OFDM), computed on the analytic signal.
4. **OFDM only**: the FFT window backs off $\lfloor N_{cp}/4\rfloor$ samples into the CP. Then a least-squares channel estimate from the preamble, a noise-variance estimate, and ZF or MMSE equalization.
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
