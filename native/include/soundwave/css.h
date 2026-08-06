// CSS (Chirp Spread Spectrum) modem — modulation and demodulation.
// Uses linear frequency-modulated chirps over configurable bandwidth.
// Spreading factor: 7..12, Bandwidth: 1-4 kHz, Sample rate: 44100 Hz.

#ifndef SOUNDWAVE_CSS_H
#define SOUNDWAVE_CSS_H

#include <stddef.h>
#include <stdint.h>

#include "soundwave/types.h"

typedef struct {
    int    sf;              // Spreading factor 7..12
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

// Full CSS demodulation: detect preamble, extract symbols, reassemble bits.
uint8_t* css_demodulate_frame(const float* samples, size_t len,
                               const css_config_t* cfg, size_t* out_bytes);

// New task-specific signatures (Issue 19 & 24)
sw_signal css_generate_chirp(double f0, double B, double T, double A, double phi0, double fs);
sw_signal css_generate_upchirp(sw_config cfg);
sw_signal css_generate_downchirp_signal(sw_config cfg);
sw_signal css_modulate_symbol(int bit, sw_config cfg);
sw_signal css_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg);

uint8_t* css_demodulate(const float* samples, size_t len, sw_config cfg, size_t* out_bytes);
int css_detect_and_sync(const float* samples, int len, int SF, int N, float* timing_offset);
void css_generate_downchirp(int N, float fs, float f0, float B, float* out);

#endif // SOUNDWAVE_CSS_H
