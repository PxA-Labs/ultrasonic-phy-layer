// Frame synchronization: matched filter, threshold detection, Zadoff-Chu correlation.
// References: MATHEMATICAL_MODEL.md section 3.1-3.2.

#include "soundwave/sync.h"
#include "soundwave/common.h"
#include "soundwave/css.h"
#include "soundwave/cfo.h"
#include "soundwave/simd_util.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

void sync_matched_filter(const float* y, size_t y_len,
                         const float* s, size_t s_len, float* R) {
    // R must hold y_len - s_len + 1 outputs; y_len < s_len would wrap the
    // unsigned bound and run far past both buffers.
    if (!y || !s || !R || s_len == 0 || y_len < s_len) return;
    for (size_t m = 0; m <= y_len - s_len; m++) {
        R[m] = simd_dot_product(y + m, s, s_len);
    }
}

int sync_detect_preamble(const float* R, size_t R_len,
                         float threshold, float noise_var,
                         size_t* frame_start) {
    if (!R || !frame_start || R_len == 0) return 0;
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
        simd_complex_dot_product(y_real + m, y_imag + m, zc_real, zc_imag, zc_len, &sum_real, &sum_imag);
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
        // CSS: preamble search over the whole buffer (css_demodulate.c).
        sw_config c;
        memset(&c, 0, sizeof c);
        c.sample_rate = (isfinite(cfg->sample_rate) && cfg->sample_rate >= 1000.0f &&
                         cfg->sample_rate <= 1.0e6f) ? (int)cfg->sample_rate : 0;
        c.sf = cfg->sf;
        c.carrier_freq = cfg->carrier_freq;
        c.bandwidth = cfg->bandwidth;
        css_geometry_t g;
        css_sync_result_t r;
        if (css_geometry(&c, &g) != 0 ||
            css_detect_frame(samples, len, &g, cfg->threshold, &r) != 1)
            return 0;
        *frame_start = (size_t)(r.start + 0.5);
        *detected_snr = r.snr_db;
        return 1;

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
        if (sync_real_to_analytic(samples, len, ar, ai) != 0) {
            free(ar); free(ai);
            return 0;
        }
        
        size_t max_d = len - 2 * N_period;
        float* M = (float*)calloc(max_d + 1, sizeof(float));
        if (!M) {
            free(ar); free(ai);
            return 0;
        }
        
        // Normalised Schmidl-Cox metric M(d) = |P(d)|^2 / (R1(d) * R2(d)).
        // The textbook form divides by R2^2 (energy of the second window
        // only); at the end of a frame the first window holds loud signal and
        // the second near-silence, so |P|^2 ~ S^2 N^2 over R2^2 ~ N^4 explodes
        // and the "peak" lands after the frame. By Cauchy-Schwarz the
        // two-sided form is bounded by 1 and reaches it only where the two
        // windows genuinely repeat (the preamble).
        //
        // Energy gate: being scale-invariant, M also rates low-level
        // *structured* residue highly (FFT-Hilbert leakage and circular
        // wrap-around ringing in a quiet tail repeat far better than noise).
        // A real preamble is among the most energetic windows, so windows
        // below SYNC_ENERGY_GATE of the peak window energy cannot win.
        float* E = (float*)malloc((max_d + 1) * sizeof(float));
        if (!E) {
            free(M); free(ar); free(ai);
            return 0;
        }
        double max_energy = 0.0;
        for (size_t d = 0; d <= max_d; d++) {
            double P_real = 0.0, P_imag = 0.0, R1 = 0.0, R2 = 0.0;
            for (size_t n = 0; n < N_period; n++) {
                double yr1 = ar[d + n];
                double yi1 = ai[d + n];
                double yr2 = ar[d + n + N_period];
                double yi2 = ai[d + n + N_period];
                
                P_real += yr1 * yr2 + yi1 * yi2;
                P_imag += yr1 * yi2 - yi1 * yr2;
                R1 += yr1 * yr1 + yi1 * yi1;
                R2 += yr2 * yr2 + yi2 * yi2;
            }
            M[d] = (float)((P_real * P_real + P_imag * P_imag) / (R1 * R2 + 1e-20));
            double energy = sqrt(R1 * R2);
            E[d] = (float)energy;
            if (energy > max_energy) max_energy = energy;
        }
        const double SYNC_ENERGY_GATE = 0.25;
        for (size_t d = 0; d <= max_d; d++) {
            if ((double)E[d] < SYNC_ENERGY_GATE * max_energy) M[d] = 0.0f;
        }
        free(E);
        
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
        if (peak_val > 0.2f) {
            *frame_start = peak_idx;
            *detected_snr = 10.0f * log10f(peak_val / (1.0f - peak_val + 1e-10f));
            return 1;
        }
        return 0;
    }

    return 0;
}
