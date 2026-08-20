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

This will produce the `soundwave-cli` executable inside the build folder.

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
*Output:*
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
