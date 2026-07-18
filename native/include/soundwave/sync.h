// Frame synchronization — matched filter (CSS) and Zadoff-Chu correlation (OFDM).
// Also provides noise variance estimation and threshold-based detection.

#ifndef SOUNDWAVE_SYNC_H
#define SOUNDWAVE_SYNC_H

#include <stddef.h>

typedef struct {
    int    mode;              // 0=CSS, 1=OFDM
    float  threshold;         // Detection threshold theta (default 3.0)
    int    zc_root;           // Zadoff-Chu root index for OFDM (default 1)
    int    zc_length;         // ZC sequence length (default 127)
    int    matched_filter_len; // CSS preamble template length
} sync_config_t;

// Matched filter cross-correlation: R_ys[m] = sum y[n+m] * s[n]
void sync_matched_filter(const float* y, size_t y_len,
                         const float* s, size_t s_len, float* R);

// Peak detection with noise-normalized threshold.
int  sync_detect_preamble(const float* R, size_t R_len,
                          float threshold, float noise_var,
                          size_t* frame_start);

// Noise variance estimation: sigma^2 = (1/N) * sum samples[n]^2
float sync_estimate_noise(const float* samples, size_t len);

// Zadoff-Chu sequence generation: CAZAC with const amplitude, zero autocorrelation.
void sync_zc_generate(int root, int length,
                      float* zc_real, float* zc_imag);

// ZC cross-correlation in complex domain.
void sync_zc_correlate(const float* y_real, const float* y_imag, size_t len,
                       const float* zc_real, const float* zc_imag, size_t zc_len,
                       float* R);

// Top-level frame detection (dispatches to CSS or OFDM method).
int  sync_detect_frame(const float* samples, size_t len,
                       const sync_config_t* cfg,
                       size_t* frame_start, float* detected_snr);

#endif // SOUNDWAVE_SYNC_H
