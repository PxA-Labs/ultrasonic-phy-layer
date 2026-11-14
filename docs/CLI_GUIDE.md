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

- **Frame format.** `modulate` wraps the text in the app's PHY frame, `[CRC-32 LE][payload 1..219 B][RS parity 32 B]` ([specification](DEVELOPER_GUIDE.md#phy-frame-format)). CLI WAVs decode in the app's *Import Signal* and app recordings decode with `demodulate`, given the same modem settings (the defaults match the app's).
- **`--sf` sets the CSS symbol:** each chirp carries SF bits and lasts 2^SF / B (SF 6..10; 127.7 ms and 62.6 bit/s raw at the default SF 8, 2 kHz). The chirp duration follows from `--sf` and `--bw`; there is no separate option. Pass the same `--sf` and `--bw` to `modulate` and `demodulate`. Use `--ofdm-mod bpsk` for BPSK OFDM.
- **`--freq` / `--bw`** set the CSS chirp and the **OFDM band** `freq ± bw/2` (default 18–20 kHz). An OFDM band that reaches DC, comes within one subcarrier of Nyquist or holds fewer than 4 subcarriers is rejected.
- `demodulate --mode css` searches the **whole file** for the first complete preamble, so any amount of silence, noise or other audio may precede the frame (fixed Nov 2026; before, a frame more than a few milliseconds into the file was usually missed). The `DEBUG: sw_detect_frame ... frame_start = N` line reports the same start. The CLI demodulates from that start, as the app does.
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
- `--input "<text>"`: The ASCII string to encode (up to 219 bytes).
- `--output <filename.wav>`: Destination path for the generated audio file.

### Options
- `--sf <sf>`: CSS spreading factor, SF bits per chirp (6..10, default `8`).
- `--fft <size>`: OFDM FFT size (256, 512, 1024, 2048, default `256`).
- `--cp <length>`: OFDM cyclic prefix length (default `64`).
- `--freq <freq_hz>`: Carrier frequency in Hz (default `19000.0`; OFDM band centre).
- `--bw <bw_hz>`: Bandwidth in Hz (default `2000.0`; OFDM band = `freq ± bw/2`).
- `--ofdm-mod <bpsk|qpsk>`: OFDM subcarrier mapping (default `qpsk`).
- `--no-rs`: frames without Reed-Solomon parity (the app's `enable_rs` off).
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
- `--sf <sf>`: CSS spreading factor, SF bits per chirp (6..10, default `8`).
- `--fft <size>`: OFDM FFT size (default `256`).
- `--cp <length>`: OFDM cyclic prefix length (default `64`).
- `--freq <freq_hz>`: Carrier frequency in Hz (default `19000.0`; OFDM band centre).
- `--bw <bw_hz>`: Bandwidth in Hz (default `2000.0`; OFDM band = `freq ± bw/2`).
- `--ofdm-mod <bpsk|qpsk>`: OFDM subcarrier mapping (default `qpsk`).
- `--no-rs`: frames without Reed-Solomon parity (the app's `enable_rs` off).
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
