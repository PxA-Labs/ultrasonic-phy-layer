// Frame synchronization: matched filter, threshold detection, Zadoff-Chu correlation.
// References: MATHEMATICAL_MODEL.md section 3.1-3.2.

#include "soundwave/sync.h"
#include "soundwave/common.h"
#include "soundwave/css.h"
#include "soundwave/cfo.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

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
    if (!samples || !cfg || !frame_start || !detected_snr) return 0;
    *frame_start = 0;
    *detected_snr = 0.0f;

    if (cfg->mode == 0) {
        // CSS Mode timing synchronization (8 up-chirps + 2 down-chirps matched filter)
        double f0 = (cfg->carrier_freq > 0.0f) ? (double)cfg->carrier_freq : 18000.0;
        double B = (cfg->bandwidth > 0.0f) ? (double)cfg->bandwidth : 4000.0;
        double fs = (cfg->sample_rate > 0.0f) ? (double)cfg->sample_rate : 44100.0;
        size_t N_pre = cfg->matched_filter_len; // symbol duration in samples
        if (N_pre <= 0) N_pre = 882; // default for fs=44100, T=0.02
        double T = (double)N_pre / fs;
        double amplitude = 0.8;
        
        sw_signal pre_up = css_generate_chirp(f0, B, T, amplitude, 0.0, fs);
        sw_signal pre_down = css_generate_chirp(f0, -B, T, amplitude, 0.0, fs);
        
        if (!pre_up.data || !pre_down.data) {
            free(pre_up.data); free(pre_down.data);
            return 0;
        }
        
        size_t max_search = len - 10 * N_pre;
        if (len < 10 * N_pre) {
            free(pre_up.data); free(pre_down.data);
            return 0;
        }

        float* power_up = (float*)calloc(max_search, sizeof(float));
        float* power_down = (float*)calloc(max_search, sizeof(float));
        if (!power_up || !power_down) {
            free(pre_up.data); free(pre_down.data);
            free(power_up); free(power_down);
            return 0;
        }
        
        for (size_t m = 0; m < max_search; m++) {
            float corr_up = 0.0f;
            float corr_down = 0.0f;
            for (size_t n = 0; n < N_pre; n++) {
                corr_up += samples[m + n] * pre_up.data[n];
                corr_down += samples[m + n] * pre_down.data[n];
            }
            power_up[m] = corr_up * corr_up;
            power_down[m] = corr_down * corr_down;
        }
        
        float max_score = 0.0f;
        int best_m = -1;
        
        for (size_t m = 0; m < max_search; m++) {
            float score = 0.0f;
            for (int i = 0; i < 8; i++) {
                if (m + i * N_pre < max_search) {
                    score += power_up[m + i * N_pre];
                }
            }
            for (int i = 8; i < 10; i++) {
                if (m + i * N_pre < max_search) {
                    score += power_down[m + i * N_pre];
                }
            }
            if (score > max_score) {
                max_score = score;
                best_m = (int)m;
            }
        }
        
        float energy_up = 0.0f;
        float energy_down = 0.0f;
        for (size_t n = 0; n < N_pre; n++) {
            energy_up += pre_up.data[n] * pre_up.data[n];
            energy_down += pre_down.data[n] * pre_down.data[n];
        }
        
        float noise_var = sync_estimate_noise(samples, len);
        float threshold = cfg->threshold * noise_var * (8.0f * energy_up * energy_up + 2.0f * energy_down * energy_down);
        
        free(power_up); free(power_down);
        free(pre_up.data); free(pre_down.data);
        
        if (best_m >= 0 && max_score >= threshold) {
            *frame_start = (size_t)best_m;
            float total_energy = 8.0f * energy_up + 2.0f * energy_down;
            *detected_snr = 10.0f * log10f((max_score / (total_energy + 1e-10f)) / (noise_var + 1e-10f));
            return 1;
        }
        return 0;

    } else if (cfg->mode == 1) {
        // OFDM timing synchronization (Schmidl-Cox timing metric on analytic signal)
        size_t N_period = cfg->matched_filter_len; // symbol period L = N + cp
        if (N_period <= 0) N_period = 256 + 32; // default
        
        if (len < 2 * N_period) return 0;

        float* ar = (float*)malloc(len * sizeof(float));
        float* ai = (float*)malloc(len * sizeof(float));
        if (!ar || !ai) {
            free(ar); free(ai);
            return 0;
        }
        sync_real_to_analytic(samples, len, ar, ai);
        
        size_t max_d = len - 2 * N_period;
        float* M = (float*)calloc(max_d + 1, sizeof(float));
        if (!M) {
            free(ar); free(ai);
            return 0;
        }
        
        for (size_t d = 0; d <= max_d; d++) {
            double P_real = 0.0, P_imag = 0.0, R = 0.0;
            for (size_t n = 0; n < N_period; n++) {
                double yr1 = ar[d + n];
                double yi1 = ai[d + n];
                double yr2 = ar[d + n + N_period];
                double yi2 = ai[d + n + N_period];
                
                P_real += yr1 * yr2 + yi1 * yi2;
                P_imag += yr1 * yi2 - yi1 * yr2;
                R += yr2 * yr2 + yi2 * yi2;
            }
            M[d] = (float)((P_real * P_real + P_imag * P_imag) / (R * R + 1e-10));
        }
        
        // Find peak of M
        size_t peak_idx = 0;
        float peak_val = M[0];
        for (size_t d = 1; d <= max_d; d++) {
            if (M[d] > peak_val) {
                peak_val = M[d];
                peak_idx = d;
            }
        }
        
        free(M); free(ar); free(ai);
        
        // Threshold check (timing metric > 0.5 indicates presence of matching symbols)
        if (peak_val > 0.5f) {
            *frame_start = peak_idx;
            *detected_snr = 10.0f * log10f(peak_val / (1.0f - peak_val + 1e-10f));
            return 1;
        }
        return 0;
    }

    return 0;
}
