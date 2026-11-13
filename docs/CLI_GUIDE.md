# Soundwave CLI Guide

The Soundwave CLI (`soundwave-cli`) is a developer command-line tool built to generate, analyze, and simulate acoustic signals for the Soundwave ultrasonic communication protocol. It supports three major commands: `modulate`, `demodulate`, and `simulate`.

---

## Building the CLI Target

To build the executable, run the following commands in the `native` directory:

```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --target soundwave_cli
```

This will produce the `soundwave-cli` executable inside the build folder (with MSVC, in `Release/` or `Debug/`). The CLI is not built for Android.

### Notes on the current implementation

- **Frame format.** `modulate` wraps the text as `[CRC-32][length u16][payload][RS parity 32 B]`. This is **not** the app's frame format (the app has no length field), so CLI WAVs cannot be decoded by the app's *Import Signal*, and app recordings cannot be decoded by `demodulate`. See [Architecture](architecture/overview.md#frame-formats).
- **`--sf` has no effect** on the CSS waveform: CSS sends one bit per chirp. The CLI has no option for the chirp duration (fixed at 20 ms) or for BPSK (OFDM is always QPSK here).
- **`--freq` / `--bw` affect CSS only.** The OFDM band is set by `--fft` and the sample rate.
- `demodulate --mode css` expects the frame near the **start** of the file. Its synchronizer accepts the first correlation value above an absolute threshold and then searches only half a chirp further, so a frame preceded by more than a few milliseconds of audio (for example a field recording) usually fails with a CRC or RS error. The `DEBUG: sw_detect_frame ... frame_start = N` line (a global peak search) gives the true offset: trim the file there and decode again. `ber_sweep.py` does this automatically. Found while building the BER sweep tool (CI smoke test, Nov 2026).
- `demodulate` decodes the **first** frame found in the file. It prints the payload on stdout and diagnostics on stderr, including a `DEBUG: sw_detect_frame ... snr = X dB` line with an uncalibrated SNR estimate. The exit code is 0 only if RS decoding and the CRC succeed.
- `simulate` sets the noise power from the average power of the **whole file**, including any silence. It uses an unseeded C `rand()`, so every run adds the same noise sequence.
- For repeated measurements over many frames (field recordings or AWGN sweeps), use [`docs/testing/ber_sweep.py`](testing/ber_sweep.py), described in the [field test plan](testing/FIELD_TEST_PLAN.md).

---

## 1. Signal Modulation (`modulate`)

Converts an ASCII text payload into a 16-bit PCM mono 44.1 kHz WAV audio file using Chirp Spread Spectrum (CSS) or Orthogonal Frequency Division Multiplexing (OFDM).

### Usage
```bash
soundwave-cli modulate --mode <css|ofdm> --input "<text>" --output <filename.wav> [options]
```

### Required Arguments
- `--mode <css|ofdm>`: The modulation technique.
- `--input "<text>"`: The ASCII string to encode (up to 217 bytes).
- `--output <filename.wav>`: Destination path for the generated audio file.

### Options
- `--sf <sf>`: CSS spreading factor (7..12, default `8`).
- `--fft <size>`: OFDM FFT size (256, 512, 1024, 2048, default `256`).
- `--cp <length>`: OFDM cyclic prefix length (default `64`).
- `--freq <freq_hz>`: Carrier frequency in Hz (default `19000.0`).
- `--bw <bw_hz>`: Bandwidth in Hz (default `2000.0`).
- `--amp <amplitude>`: Waveform amplitude scaling (0.0 to 1.0, default `0.8`).

### Examples
#### CSS Modulation
```bash
./soundwave-cli modulate --mode css --input "Hello Soundwave" --output css_frame.wav --sf 8 --freq 19000 --bw 2000
```

#### OFDM Modulation
```bash
./soundwave-cli modulate --mode ofdm --input "Hello OFDM World" --output ofdm_frame.wav --fft 256 --cp 64 --freq 18500
```

---

## 2. Signal Demodulation (`demodulate`)

Reads a WAV audio file, synchronizes the frame, applies frequency offset (CFO) estimation and correction, performs channel equalization, decodes the Reed-Solomon/CRC error correction layers, and outputs the extracted payload to stdout.

### Usage
```bash
soundwave-cli demodulate --mode <css|ofdm> --input <filename.wav> [options]
```

### Required Arguments
- `--mode <css|ofdm>`: Modulation scheme matching the generated wave.
- `--input <filename.wav>`: Input WAV audio file containing the sound wave.

### Options
- `--sf <sf>`: CSS spreading factor (7..12, default `8`).
- `--fft <size>`: OFDM FFT size (default `256`).
- `--cp <length>`: OFDM cyclic prefix length (default `64`).
- `--freq <freq_hz>`: Carrier frequency in Hz (default `19000.0`).
- `--bw <bw_hz>`: Bandwidth in Hz (default `2000.0`).
- `--equalizer <zf|mmse>`: Channel equalization method for OFDM (default `zf`).

### Examples
#### Demodulating a CSS Signal
```bash
./soundwave-cli demodulate --mode css --input css_frame.wav
```
*Output (stdout, then the last stderr line):*
```text
Hello Soundwave
Demodulation successful! (Errors corrected: 0)
```

#### Demodulating an OFDM Signal
```bash
./soundwave-cli demodulate --mode ofdm --input ofdm_frame.wav --equalizer mmse
```
*Output:*
```text
Hello OFDM World
Demodulation successful! (Errors corrected: 0)
```

---

## 3. AWGN Channel Simulation (`simulate`)

Injects Additive White Gaussian Noise (AWGN) to an input audio wave to model a noisy communication channel at a specified Signal-to-Noise Ratio (SNR) in dB.

### Usage
```bash
soundwave-cli simulate --input <input.wav> --snr <snr_db> --output <output.wav>
```

### Required Arguments
- `--input <input.wav>`: Clean source WAV file.
- `--snr <snr_db>`: Target Signal-to-Noise Ratio in dB. Lower values add more noise.
- `--output <output.wav>`: Noisy output WAV file.

### Example
#### Add 10 dB SNR AWGN noise to a modulated frame
```bash
./soundwave-cli simulate --input css_frame.wav --snr 10 --output noisy_css_frame.wav
```
*Output:*
```text
Successfully simulated AWGN channel on 'css_frame.wav' -> 'noisy_css_frame.wav' (SNR: 10.0 dB)
```

To verify the robust Reed-Solomon recovery under noise, you can attempt to demodulate the noisy wave:
```bash
./soundwave-cli demodulate --mode css --input noisy_css_frame.wav
```
