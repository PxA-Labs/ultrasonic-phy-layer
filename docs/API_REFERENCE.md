# C API Reference (`soundwave_api.h`)

This page is maintained by hand and checked against `native/include/soundwave_api.h`, `native/include/soundwave/types.h` and `native/src/api/` (`soundwave_api.c`, `ffi_helpers.c`). The [Doxygen reference](api/c/html/index.html) is generated from the header comments on every docs build. Where a header comment and the implementation disagree, this page follows the implementation and says so.

- Linkage: `extern "C"`. Symbols are exported with `SW_API` (`__declspec(dllexport)` when building the Windows DLL, `visibility("default")` elsewhere).
- Version macro: `SW_VERSION "1.0.0"`.
- Return convention: `int` status, `SW_OK` (0) on success, a negative `sw_error_t` otherwise.
- Memory: the **caller allocates** all output buffers. The library never keeps or frees caller pointers. Handles returned by `*_start` / `*_create` are owned by the library and freed by the matching `*_stop` / `*_destroy`.

## Status codes (`sw_error_t`)

| Code | Value | Returned when |
|---|---|---|
| `SW_OK` | 0 | Success |
| `SW_ERR_BAD_PARAM` | −1 | NULL pointer, zero length/capacity, or a config rejected by `sw_config_validate` |
| `SW_ERR_MEMORY` | −2 | Allocation failed |
| `SW_ERR_DECODE` | −3 | Reed-Solomon decode failed (more than t errors) |
| `SW_ERR_SYNC` | −4 | No preamble found, or too few samples for sync/CFO |
| `SW_ERR_AUDIO` | −5 | Audio device error |
| `SW_ERR_NOT_IMPLEMENTED` | −6 | Feature not implemented |
| `SW_ERR_OVERFLOW` | −7 | Output buffer too small. The length out-parameter then holds the **required** size |

!!! note "Header comments that name non-existent codes"
    Some comments in `soundwave_api.h` mention `SW_ERR_DECODE_FAILED`, `SW_ERR_NOT_FOUND` and `SW_ERR_AUDIO_IO`. These codes do not exist. The functions return `SW_ERR_DECODE`, `SW_ERR_SYNC` and `SW_ERR_AUDIO` (or the backend's code) respectively.

## Configuration (`sw_config_t`)

```c
typedef struct {
    int   sample_rate;      // Hz; 0 = 44100
    int   modulation;       // 0 = CSS, 1 = OFDM
    int   sf;               // CSS spreading factor (validated 6..12; see note)
    int   num_subcarriers;  // OFDM FFT size N (power of two, 16..4096; 0 = 256)
    int   cp_length;        // OFDM cyclic prefix in samples (0..N; 0 = N/8)
    int   num_pilots;       // OFDM pilots (0..N/2; see note)
    float coding_rate;      // must be finite; currently unused by the DSP
    float threshold;        // detection threshold multiplier (>= 0)
    int   equalizer;        // 0 = ZF, 1 = MMSE
    float carrier_freq;     // Hz; CSS chirp start frequency f0 (0 = 19000)
    float bandwidth;        // Hz; CSS sweep B (0 = 2000)
    float symbol_duration;  // s; CSS chirp length T (0 = 0.02, max 1.0)
    float amplitude;        // [0, 1] (0 = 0.8)
    int   ofdm_modulation;  // 0 = BPSK, 1 = QPSK
} sw_config_t;
```

Field notes (from the implementation):

- **Zero means default** for most fields. Each module fills in its own default.
- `sf`, `coding_rate` and `num_pilots` are validated but **do not change the waveform**. CSS sends one bit per chirp (up-chirp = 0, down-chirp = 1). OFDM puts a pilot on every 8th active subcarrier regardless of `num_pilots`.
- `carrier_freq` and `bandwidth` affect **CSS only**. The OFDM band is fixed by `num_subcarriers` and `sample_rate` (see [Signal chain](architecture/signal-chain.md)).

### `sw_config_validate`

```c
int sw_config_validate(sw_config_t cfg);
```

Returns `SW_OK` or `SW_ERR_BAD_PARAM`. Every `sw_*` function that takes a config calls it first. It checks:

- `modulation`, `equalizer` and `ofdm_modulation` are each 0 or 1.
- `sample_rate` is 0 or in 8000..192000.
- All float fields are finite.
- `threshold`, `carrier_freq`, `bandwidth` and `symbol_duration` are ≥ 0.
- `carrier_freq` and `bandwidth` are ≤ Nyquist.
- `symbol_duration` ≤ 1 s.
- `amplitude` is in [0, 1].
- `sf` is 0 or 6..12.
- `num_subcarriers` is 0 or a power of two in 16..4096.
- `cp_length` is in 0..N.
- `num_pilots` is in 0..N/2.

## Library information

```c
const char* sw_version(void);   // static string, e.g. "1.0.0"
```

## CRC-32

```c
int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc);
```

IEEE 802.3 CRC-32 (reflected, polynomial `0xEDB88320`). `len == 0` yields `*crc = 0`. Returns `SW_ERR_BAD_PARAM` for NULL `data` or `crc`.

## Reed-Solomon RS(255,223)

```c
int sw_rs_encode(const uint8_t* data, size_t data_len,
                 uint8_t* parity, size_t* parity_len);
int sw_rs_decode(uint8_t* data, size_t* data_len,
                 const uint8_t* parity, size_t parity_len,
                 int* errors_corrected);
```

- `sw_rs_encode`: `data_len` must be 1..223. It writes 32 parity bytes and sets `*parity_len = 32`. Shorter messages are treated as a shortened code.
- `sw_rs_decode`: corrects up to 16 byte errors in place in `data` (the parity is read-only). Constraints: `*data_len` in 1..255, `parity_len` ≥ 2, and `*data_len + parity_len` ≤ 255. Returns `SW_ERR_DECODE` when the word is uncorrectable. On success `*errors_corrected` is 0..16.

## CSS modem

```c
int sw_css_modulate(const uint8_t* bits, size_t bit_len, sw_config_t cfg,
                    float* samples, size_t* sample_len);
int sw_css_demodulate(const float* samples, size_t sample_len, sw_config_t cfg,
                      uint8_t* bits, size_t* bit_len);
```

- **Bit packing:** `bits` is a **packed byte array** (MSB first). `bit_len` counts bits.
- **Output length:** `sw_css_modulate` produces `(10 + bit_len) × round(T·fs)` samples: an 8 up-chirp + 2 down-chirp preamble, then one chirp per bit. `*sample_len` is the capacity on input and the written count on output. On `SW_ERR_OVERFLOW` it holds the required count.
- **Demodulation:** `sw_css_demodulate` searches for the first preamble, then decodes every remaining whole chirp, so trailing noise also becomes bits. It returns packed bytes, and `*bit_len` is set to a multiple of 8. It returns `SW_ERR_SYNC` if no preamble is found and `SW_ERR_OVERFLOW` (with the required bit count) if the buffer is too small.

## OFDM modem

```c
int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len, sw_config_t cfg,
                     float* samples, size_t* sample_len);
int sw_ofdm_demodulate(const float* samples, size_t sample_len, sw_config_t cfg,
                       uint8_t* bits, size_t* bit_len);
int sw_ofdm_equalized_symbols(const float* samples, size_t sample_len,
                              sw_config_t cfg, float* iq, size_t* num_points);
```

- **Output length:** `(2 + ceil(bit_len / bits_per_symbol)) × (N + cp)` samples (two Zadoff-Chu preamble symbols). Here `bits_per_symbol` = data subcarriers × (1 for BPSK, 2 for QPSK), and the last symbol is zero-padded.
- **Demodulation:** detection, CFO correction, a preamble-based LS channel and noise estimate, then ZF or MMSE equalization (`cfg.equalizer`) and hard demapping. Bits are packed, MSB first.
- **`sw_ofdm_equalized_symbols`:** runs the same receiver but returns the equalized data-subcarrier points as interleaved `I0,Q0,I1,Q1,...` floats. Points are unit energy (BPSK ±1, QPSK (±1±j)/√2). `*num_points` is a capacity on input. Output beyond the capacity is truncated, which is **not** an error. Requires `cfg.modulation == 1`.

## Synchronization and CFO

```c
int sw_detect_frame(const float* samples, size_t len, sw_config_t cfg,
                    size_t* frame_start, float* snr);
int sw_estimate_cfo(const float* samples, size_t len, sw_config_t cfg,
                    float* cfo_hz);
```

- **`sw_detect_frame`:** finds the preamble (CSS: matched filter on the 8-up/2-down pattern; OFDM: Zadoff-Chu correlation). It writes the start offset and an SNR estimate in dB, and returns `SW_ERR_SYNC` if nothing is above threshold. For CSS mode the buffer must hold at least 10 chirps.
- **`sw_estimate_cfo`:** Schmidl-Cox estimate over two repeated periods of `N + cp` samples. It needs `len ≥ 2(N + cp)`, otherwise it returns `SW_ERR_SYNC`.

## Real-time audio I/O

```c
int sw_audio_capture_start(sw_config_t cfg, void** handle);
int sw_audio_capture_read(void* handle, float* buffer, size_t count, size_t* read);
int sw_audio_capture_stop(void* handle);

int sw_audio_playback_start(sw_config_t cfg, void** handle);
int sw_audio_playback_write(void* handle, const float* buffer, size_t count);
int sw_audio_playback_stop(void* handle);
```

- Each stream uses the default device at `cfg.sample_rate` (0 = 44100), mono, through miniaudio, with a one-second 16-bit ring buffer.
- `sw_audio_capture_read` returns as many samples as are available, up to `count`, and sets `*read`.
- `*_stop` frees the handle.
- On Android only the AAudio and OpenSL ES backends are compiled in.

## Automatic gain control

```c
int sw_agc_create(int sample_rate, float target_rms, void** handle);
int sw_agc_process(void* handle, float* samples, size_t len);   // in place
int sw_agc_get_gain_db(void* handle, float* gain_db);
int sw_agc_reset(void* handle);
int sw_agc_destroy(void* handle);
```

- `sample_rate` must be 8000..192000. `target_rms` must be in (0, 1], and 0 selects 0.25.
- Behavior: attack 1 ms, release 100 ms, 10 ms RMS window, gain 0.1–40 (−20 to +32 dB), output peak-limited to full scale. Non-finite input samples become 0.
- Handles carry a magic tag, so a stale or foreign pointer is rejected with `SW_ERR_BAD_PARAM`. Do not use a handle after `sw_agc_destroy`.

## FFI allocation helpers (exported, not declared in the header)

`native/src/api/ffi_helpers.c` exports `float* sw_alloc_float(int n)`, `double* sw_alloc_double(int n)`, `uint8_t* sw_alloc_uint8(int n)` (all `calloc`-based) and `void sw_free(void*)`. They are not declared in `soundwave_api.h`, and the Dart app does not use them (it allocates with `package:ffi`'s `calloc`).

## Minimal example (CSS round trip)

```c
#include "soundwave_api.h"
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    sw_config_t cfg = {0};          /* all defaults: CSS, 44.1 kHz, 19 kHz, 2 kHz, 20 ms */
    const uint8_t msg[] = { 'H', 'i' };
    size_t n = 0;                   /* ask for the size first */
    float probe;
    if (sw_css_modulate(msg, 16, cfg, &probe, &n) != SW_ERR_OVERFLOW) return 1;
    float* pcm = malloc(n * sizeof *pcm);
    if (sw_css_modulate(msg, 16, cfg, pcm, &n) != SW_OK) return 1;

    uint8_t out[64];
    size_t bits = sizeof out * 8;
    int rc = sw_css_demodulate(pcm, n, cfg, out, &bits);
    printf("rc=%d bits=%zu first=%c%c\n", rc, bits, out[0], out[1]);
    free(pcm);
    return rc;
}
```

A capacity of 0 is fine for the size query: `sw_css_modulate` only rejects a NULL `samples` pointer and a zero `bit_len`, and it reports the required length with `SW_ERR_OVERFLOW`. A real application wraps `msg` in a frame (CRC-32 + RS parity), as `soundwave-cli` and the app's `FrameCodec` do; see [Architecture](architecture/overview.md#frame-formats).
