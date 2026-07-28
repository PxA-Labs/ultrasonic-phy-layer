# Soundwave API & C/C++ Header Reference

This document provides a comprehensive API specification for the Soundwave Ultrasonic Physical Layer native library (`libsoundwave`). It covers the public C FFI boundary API (`soundwave_api.h`) as well as lower-level C DSP module headers.

---

## Table of Contents

1. [Error Codes & Types (`soundwave/types.h`)](#1-error-codes--types)
2. [Public C FFI Boundary API (`soundwave_api.h`)](#2-public-c-ffi-boundary-api)
   - [Library Information](#library-information)
   - [CRC-32 Checksum](#crc-32-checksum)
   - [Reed-Solomon Error Correction](#reed-solomon-error-correction)
   - [Chirp Spread Spectrum (CSS) Modem](#chirp-spread-spectrum-css-modem)
   - [OFDM Modem](#ofdm-modem)
   - [Timing Synchronization & CFO](#timing-synchronization--cfo)
   - [Real-Time Audio I/O](#real-time-audio-io)
3. [Internal DSP Module Headers](#3-internal-dsp-module-headers)
   - [Reed-Solomon Module (`soundwave/rs.h`)](#reed-solomon-module)
   - [CRC-32 Module (`soundwave/crc.h`)](#crc-32-module)

---

## 1. Error Codes & Types (`soundwave/types.h`)

All native API functions return an integer status code of type `sw_error_t`. `0` indicates success, while negative integers indicate specific failure conditions.

```c
typedef enum {
    SW_OK                  =  0,  // Operation succeeded
    SW_ERR_INVALID_ARG     = -1,  // Null pointer or out-of-bounds parameter
    SW_ERR_NOMEM           = -2,  // Memory allocation failure
    SW_ERR_OVERFLOW        = -3,  // Buffer overflow (destination buffer too small)
    SW_ERR_NOT_FOUND       = -4,  // Preamble or frame not detected
    SW_ERR_DECODE_FAILED   = -5,  // RS/FEC decode uncorrectable (> t errors)
    SW_ERR_CRC_MISMATCH    = -6,  // Frame CRC-32 integrity check failed
    SW_ERR_AUDIO_IO        = -7,  // Audio device capture/playback failure
    SW_ERR_NOT_IMPLEMENTED = -8   // Feature not yet implemented
} sw_error_t;
```

### Configuration Structure (`sw_config_t`)

```c
typedef struct {
    int   mode;               // 0 = CSS, 1 = OFDM
    int   sample_rate;        // Audio sample rate in Hz (default 44100)
    float carrier_freq;       // Center carrier frequency in Hz (default 19000.0)
    float bandwidth;          // Signal bandwidth in Hz (default 2000.0)
    int   fec_enabled;        // 1 = Enable RS(255,223), 0 = Disable
    float tx_gain;            // Transmit amplitude gain [0.0, 1.0] (default 0.8)
    int   preamble_len;       // Preamble length in samples (default 1024)
} sw_config_t;
```

---

## 2. Public C FFI Boundary API (`soundwave_api.h`)

The public C API functions use strict C linkage (`extern "C"`) and standard C scalar types compatible with `dart:ffi`.

### Library Information

#### `sw_version`
```c
SW_API const char* sw_version(void);
```
- **Description**: Returns the semantic version string of the compiled Soundwave library (e.g., `"1.0.0"`).
- **Return**: Pointer to static null-terminated C string.

---

### CRC-32 Checksum

#### `sw_crc32`
```c
SW_API int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc);
```
- **Description**: Computes IEEE 802.3 CRC-32 checksum ($G(x) = \text{0xED888320}$) over input data.
- **Parameters**:
  - `data` `[in]`: Pointer to input byte array.
  - `len` `[in]`: Number of bytes in `data`.
  - `crc` `[out]`: Pointer to output `uint32_t` variable.
- **Return**: `SW_OK` on success, `SW_ERR_INVALID_ARG` if pointers are null.

---

### Reed-Solomon Error Correction

#### `sw_rs_encode`
```c
SW_API int sw_rs_encode(const uint8_t* data, size_t data_len,
                        uint8_t* parity, size_t* parity_len);
```
- **Description**: Encodes input data bytes using Reed-Solomon over $GF(2^8)$, generating parity bytes.
- **Parameters**:
  - `data` `[in]`: Pointer to input message bytes ($K \le 223$).
  - `data_len` `[in]`: Number of bytes in `data`.
  - `parity` `[out]`: Pre-allocated buffer to receive 32 parity bytes.
  - `parity_len` `[out]`: Pointer to variable filled with written parity length (32).
- **Return**: `SW_OK` on success, `SW_ERR_INVALID_ARG` or `SW_ERR_OVERFLOW`.

#### `sw_rs_decode`
```c
SW_API int sw_rs_decode(uint8_t* data, size_t* data_len,
                        const uint8_t* parity, size_t parity_len,
                        int* errors_corrected);
```
- **Description**: Decodes codeword and corrects up to $t=16$ symbol errors in-place using Berlekamp-Massey, Chien Search, and Forney algorithms.
- **Parameters**:
  - `data` `[in, out]`: Pointer to message data bytes (corrected in-place).
  - `data_len` `[in, out]`: Pointer to message data length.
  - `parity` `[in]`: Pointer to 32 parity bytes.
  - `parity_len` `[in]`: Parity length (32).
  - `errors_corrected` `[out]`: Pointer receiving number of corrected symbol errors (0 to 16).
- **Return**: `SW_OK` on success, `SW_ERR_DECODE_FAILED` if errors $> 16$ (uncorrectable).

---

### Chirp Spread Spectrum (CSS) Modem

#### `sw_css_modulate`
```c
SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len);
```
- **Description**: Modulates raw bit stream into continuous Linear Frequency Modulated (LFM) chirp audio samples.
- **Parameters**:
  - `bits` `[in]`: Pointer to input bit array (1 bit per element or packed bytes).
  - `bit_len` `[in]`: Number of bits.
  - `cfg` `[in]`: Modem configuration struct (`sw_config_t`).
  - `samples` `[out]`: Pre-allocated float buffer to receive output PCM samples.
  - `sample_len` `[in, out]`: Pointer to capacity (in), receives actual sample count (out).
- **Return**: `SW_OK` on success, `SW_ERR_OVERFLOW` if `samples` buffer is too small.

#### `sw_css_demodulate`
```c
SW_API int sw_css_demodulate(const float* samples, size_t sample_len,
                             sw_config_t cfg, uint8_t* bits, size_t* bit_len);
```
- **Description**: Demodulates audio PCM samples into bit stream using dechirping and FFT peak detection.
- **Parameters**:
  - `samples` `[in]`: Pointer to input float PCM samples.
  - `sample_len` `[in]`: Sample count.
  - `cfg` `[in]`: Modem configuration struct.
  - `bits` `[out]`: Pre-allocated output bit buffer.
  - `bit_len` `[in, out]`: Receives demodulated bit count.
- **Return**: `SW_OK` on success.

---

### OFDM Modem

#### `sw_ofdm_modulate`
```c
SW_API int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len,
                            sw_config_t cfg, float* samples, size_t* sample_len);
```
- **Description**: Performs constellation mapping (BPSK/QPSK), IDFT via KissFFT, and Cyclic Prefix insertion to generate OFDM acoustic symbols.

#### `sw_ofdm_demodulate`
```c
SW_API int sw_ofdm_demodulate(const float* samples, size_t sample_len,
                              sw_config_t cfg, uint8_t* bits, size_t* bit_len);
```
- **Description**: Removes Cyclic Prefix, computes DFT via KissFFT, performs LS channel estimation and equalization, and extracts payload bits.

---

### Timing Synchronization & CFO

#### `sw_detect_frame`
```c
SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr);
```
- **Description**: Detects preamble offset in continuous audio buffer using matched filtering (CSS) or Zadoff-Chu correlation (OFDM).
- **Parameters**:
  - `samples` `[in]`: Pointer to audio sample buffer.
  - `len` `[in]`: Buffer length in float samples.
  - `cfg` `[in]`: Modem configuration struct.
  - `frame_start` `[out]`: Receives sample offset index of detected preamble start.
  - `snr` `[out]`: Receives estimated Signal-to-Noise Ratio (dB) at peak.
- **Return**: `SW_OK` (1) if frame detected, `SW_ERR_NOT_FOUND` (0) if no preamble exceeds threshold.

#### `sw_estimate_cfo`
```c
SW_API int sw_estimate_cfo(const float* samples, size_t len,
                           sw_config_t cfg, float* cfo_hz);
```
- **Description**: Estimates Carrier Frequency Offset (CFO) in Hz using Schmidl-Cox preamble correlation.

---

### Real-Time Audio I/O

#### `sw_audio_capture_start` / `sw_audio_playback_start`
```c
SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle);
SW_API int sw_audio_playback_start(sw_config_t cfg, void** handle);
```
- **Description**: Initializes `miniaudio` capture or playback stream at 44.1 kHz, 16-bit PCM mono. Returns opaque handle.

---

## 3. Internal DSP Module Headers

### Reed-Solomon Module (`soundwave/rs.h`)

- `uint8_t gf_mul(uint8_t a, uint8_t b)`: Galois Field $GF(2^8)$ multiplication ($p(x) = x^8+x^4+x^3+x^2+1$).
- `uint8_t gf_add(uint8_t a, uint8_t b)`: Galois Field addition (bitwise XOR).
- `uint8_t gf_div(uint8_t a, uint8_t b)`: Galois Field division via log/exp lookup tables.
- `int rs_berlekamp_massey_len(const uint8_t* S, int num_syndromes, uint8_t* lambda, uint8_t* omega)`: Solves error locator polynomial $\Lambda(x)$.
- `void rs_chien_search_n(const uint8_t* lambda, int degree, size_t n, int* error_pos, int* count)`: Finds error positions.
- `void rs_forney_n(const uint8_t* omega, const uint8_t* lambda, const int* pos, int count, size_t n, uint8_t* mag)`: Computes error magnitudes.
