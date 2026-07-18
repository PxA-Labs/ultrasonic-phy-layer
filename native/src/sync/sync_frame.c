// Frame synchronization: matched filter, threshold detection, Zadoff-Chu correlation.
// References: MATHEMATICAL_MODEL.md section 3.1-3.2.

#include "soundwave/sync.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>

void sync_matched_filter(const float* y, size_t y_len,
                         const float* s, size_t s_len, float* R) {
    for (size_t m = 0; m <= y_len - s_len; m++) {
        double sum = 0.0;
        for (size_t n = 0; n < s_len; n++)
            sum += (double)y[m + n] * (double)s[n];
        R[m] = (float)sum;
    }
}

int sync_detect_preamble(const float* R, size_t R_len,
                         float threshold, float noise_var,
                         size_t* frame_start) {
    size_t peak_idx = 0;
    float peak_val = R[0];
    for (size_t i = 1; i < R_len; i++) {
        if (R[i] > peak_val) {
            peak_val = R[i];
            peak_idx = i;
        }
    }
    if (peak_val * peak_val > threshold * noise_var) {
        *frame_start = peak_idx;
        return 1;
    }
    return 0;
}

float sync_estimate_noise(const float* samples, size_t len) {
    double sum_sq = 0.0;
    for (size_t i = 0; i < len; i++)
        sum_sq += (double)samples[i] * (double)samples[i];
    return (float)(sum_sq / (double)len);
}

void sync_zc_generate(int root, int length, float* zc_real, float* zc_imag) {
    for (int n = 0; n < length; n++) {
        float angle = -SW_PI * (float)root * (float)n * (float)(n + 1) / (float)length;
        zc_real[n] = cosf(angle);
        zc_imag[n] = sinf(angle);
    }
}

void sync_zc_correlate(const float* y_real, const float* y_imag, size_t len,
                       const float* zc_real, const float* zc_imag, size_t zc_len,
                       float* R) {
    for (size_t m = 0; m <= len - zc_len; m++) {
        double sum_real = 0.0, sum_imag = 0.0;
        for (size_t n = 0; n < zc_len; n++) {
            sum_real += (double)y_real[m + n] * (double)zc_real[n]
                      + (double)y_imag[m + n] * (double)zc_imag[n];
            sum_imag += (double)y_imag[m + n] * (double)zc_real[n]
                      - (double)y_real[m + n] * (double)zc_imag[n];
        }
        R[m] = (float)(sum_real * sum_real + sum_imag * sum_imag);
    }
}

int sync_detect_frame(const float* samples, size_t len,
                      const sync_config_t* cfg,
                      size_t* frame_start, float* detected_snr) {
    (void)samples; (void)len; (void)cfg;
    *frame_start = 0;
    *detected_snr = 0.0f;
    return 0; // TODO: dispatch based on cfg->mode
}
