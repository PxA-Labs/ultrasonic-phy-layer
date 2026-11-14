// CSS (Chirp Spread Spectrum) modem — modulation and demodulation.
//
// Frame-level modem (css_modulate / css_demodulate / css_detect_frame):
// LoRa-style symbols. Each data symbol is the base up-chirp cyclically
// shifted by k chips, k in [0, 2^SF), so one chirp carries SF bits (Gray
// mapped). The band is carrier_freq +/- B/2 with B quantised to fs / D for an
// integer D samples per chip (see css_geometry). Frames are
//   [8 base up-chirps][2 down-chirps][data up-chirps ...]
// Data never contains a down-chirp, so the preamble cannot be reproduced by
// a payload. See docs/MATHEMATICAL_MODEL.md sections 2.1 and 3.1.

#ifndef SOUNDWAVE_CSS_H
#define SOUNDWAVE_CSS_H

#include <stddef.h>
#include <stdint.h>

#include "soundwave/types.h"

// Supported spreading factors for the frame-level modem. SF bounds are
// justified in MATHEMATICAL_MODEL.md section 2.1.5 (bin spacing B / 2^SF vs.
// clock/Doppler offsets; symbol duration <= 1 s).
#define CSS_MIN_SF            6
#define CSS_MAX_SF            10
#define CSS_DEFAULT_SF        8
#define CSS_PREAMBLE_UP       8
#define CSS_PREAMBLE_DOWN     2
#define CSS_PREAMBLE_SYMBOLS  (CSS_PREAMBLE_UP + CSS_PREAMBLE_DOWN)
#define CSS_MAX_SYMBOL_SEC    1.0

// Derived CSS waveform parameters (defaults applied, validated).
typedef struct {
    int    sf;        // spreading factor
    int    M;         // chips per symbol = 2^sf
    int    D;         // samples per chip = round(fs / bandwidth), >= 1
    int    N;         // samples per symbol = M * D
    double fs;        // sample rate (Hz)
    double fc;        // band centre (Hz)
    double B;         // effective bandwidth fs / D (Hz)
    double amplitude; // peak amplitude
} css_geometry_t;

// Applies the module defaults to zero fields (fs 44100, sf 8, carrier 19 kHz,
// bandwidth 2 kHz, amplitude 0.8) and derives the geometry. Returns 0, or -1
// if the configuration cannot be modulated: sf outside CSS_MIN_SF..MAX_SF,
// non-finite values, band [fc - B/2, fc + B/2] outside (0, fs/2], or a symbol
// longer than CSS_MAX_SYMBOL_SEC. cfg.symbol_duration is not used: a CSS
// symbol always lasts 2^SF / B.
int    css_geometry(const sw_config* cfg, css_geometry_t* g);

// Data symbols needed for num_bits (ceil(num_bits / sf)).
size_t css_num_symbols(const css_geometry_t* g, size_t num_bits);

// Samples in a frame carrying num_bits (preamble + data); 0 if it would
// overflow size_t.
size_t css_frame_samples(const css_geometry_t* g, size_t num_bits);

// Writes css_frame_samples(g, num_bits) samples to out. bits are read MSB
// first; the last symbol is zero padded.
void   css_modulate_into(const css_geometry_t* g, const uint8_t* bits,
                         size_t num_bits, float* out);

typedef struct {
    double start;   // preamble start in samples (fractional)
    double cfo_hz;  // estimated carrier/Doppler offset (Hz)
    float  rho;     // mean normalised preamble correlation in [0, 1]
    float  snr_db;  // in-band SNR estimate rho / (1 - rho), dB
} css_sync_result_t;

// Searches the whole buffer for the first complete preamble. threshold is
// sw_config.threshold (<= 0 or non-finite selects 3). Returns 1 if found,
// 0 if not, -1 on allocation failure or invalid arguments.
int    css_detect_frame(const float* samples, size_t len, const css_geometry_t* g,
                        float threshold, css_sync_result_t* res);

// --- Legacy single-chirp helpers (css_config_t; raw, no framing) ---------

typedef struct {
    int    sf;              // Spreading factor
    float  bandwidth;       // Sweep bandwidth in Hz
    float  sample_rate;     // Sample rate in Hz
    float  f0;              // Start frequency in Hz
    int    chirp_len;       // Chirp length in samples (computed)
} css_config_t;

void css_init(css_config_t* cfg);

// Generate base upchirp: s[n] = cos(2pi * (f0 * n/fs + (mu/2) * (n/fs)^2))
void css_generate_upchirp_raw(const css_config_t* cfg, float* chirp);

// Modulate one symbol: shift chirp by (sym / 2^sf) * bandwidth.
void css_modulate_symbol_raw(const css_config_t* cfg, int sym_value, float* symbol);

// Generate downchirp (conjugate/negative-phase of upchirp).
void css_generate_downchirp_raw(const css_config_t* cfg, float* downchirp);

// Dechirp: multiply samples by downchirp to extract tone.
void css_dechirp(const float* samples, int N, const float* downchirp,
                 float* dechirped, int N_fft);

// Extract one symbol from dechirped signal via FFT peak detection.
int  css_extract_symbol(const float* samples, int N,
                        const float* downchirp, int N_fft, int SF);

// Linear chirp from f0 sweeping B Hz (B < 0: down) over T seconds.
sw_signal css_generate_chirp(double f0, double B, double T, double A, double phi0, double fs);

// --- Frame-level modem --------------------------------------------------

// Preamble + Gray-mapped SF-bit symbols. Empty signal on invalid config.
sw_signal css_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg);

// Finds the first frame, then demodulates every complete symbol after the
// preamble to the end of the buffer (SF bits each, MSB first). Returns a
// malloc'd buffer of *out_bytes bytes, or NULL if no frame was found.
uint8_t* css_demodulate(const float* samples, size_t len, sw_config cfg, size_t* out_bytes);

#endif // SOUNDWAVE_CSS_H
