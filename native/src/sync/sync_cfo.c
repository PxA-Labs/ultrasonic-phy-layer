// CFO estimation (Schmidl-Cox) and frequency offset correction.
// References: MATHEMATICAL_MODEL.md section 3.3.

#include "soundwave/cfo.h"
#include "soundwave/common.h"
#include "kiss_fft.h"
#include <string.h>
#include <math.h>

void sync_real_to_analytic(const float* real, size_t len,
                           float* analytic_real, float* analytic_imag) {
    int N = (int)len;
    kiss_fft_cpx* fft_in = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* fft_out = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    for (int i = 0; i < N; i++) {
        fft_in[i].r = real[i];
        fft_in[i].i = 0.0f;
    }
    kiss_fft_cfg fwd = kiss_fft_alloc(N, 0, NULL, NULL);
    kiss_fft_cfg inv = kiss_fft_alloc(N, 1, NULL, NULL);
    kiss_fft(fwd, fft_in, fft_out);
    // Zero negative frequencies, double positive
    for (int i = 0; i < N; i++) {
        if (i == 0 || i == N / 2)
            fft_out[i].i = 0.0f; // DC and Nyquist: real-only
        else if (i < N / 2)
            fft_out[i].r *= 2.0f; // positive freqs
        else
            fft_out[i].r = fft_out[i].i = 0.0f; // negative freqs
    }
    kiss_fft(inv, fft_out, fft_in);
    for (int i = 0; i < N; i++) {
        analytic_real[i] = fft_in[i].r / (float)N;
        analytic_imag[i] = fft_in[i].i / (float)N;
    }
    free(fft_in); free(fft_out); free(fwd); free(inv);
}

float sync_schmidl_cox_cfo(const float* y, size_t len, int N, float fs) {
    float* ar = (float*)malloc(len * sizeof(float));
    float* ai = (float*)malloc(len * sizeof(float));
    sync_real_to_analytic(y, len, ar, ai);
    double sum_real = 0.0, sum_imag = 0.0;
    for (int n = 0; n < N; n++) {
        sum_real += (double)ar[n] * (double)ar[n + N]
                  + (double)ai[n] * (double)ai[n + N];
        sum_imag += (double)ar[n] * (double)ai[n + N]
                  - (double)ai[n] * (double)ar[n + N];
    }
    free(ar); free(ai);
    return fs / (SW_TWO_PI * (float)N) * atan2f((float)sum_imag, (float)sum_real);
}

void sync_correction_phasor(float cfo, float fs, size_t len,
                            float* corr_real, float* corr_imag) {
    for (size_t n = 0; n < len; n++) {
        float angle = -SW_TWO_PI * cfo / fs * (float)n;
        corr_real[n] = cosf(angle);
        corr_imag[n] = sinf(angle);
    }
}

void sync_apply_cfo_correction(const float* y_real, const float* y_imag,
                               size_t len, float cfo, float fs,
                               float* out_real) {
    float* cr = (float*)malloc(len * sizeof(float));
    float* ci = (float*)malloc(len * sizeof(float));
    sync_correction_phasor(cfo, fs, len, cr, ci);
    for (size_t n = 0; n < len; n++)
        out_real[n] = y_real[n] * cr[n] - y_imag[n] * ci[n];
    free(cr); free(ci);
}

void sync_schmidl_cox_timing(const float* y, size_t len, int N, float* M) {
    for (size_t d = 0; d <= len - 2 * (size_t)N; d++) {
        double P_real = 0.0, P_imag = 0.0, R = 0.0;
        for (int n = 0; n < N; n++) {
            P_real += (double)y[d + n] * (double)y[d + n + N];
            P_imag += (double)y[d + n] * (double)y[d + n + N]; // simplified
            R += (double)y[d + n + N] * (double)y[d + n + N];
        }
        M[d] = (float)((P_real * P_real + P_imag * P_imag) / (R * R + 1e-10));
    }
}

int sync_find_timing_peak(const float* M, size_t len, size_t* timing_idx) {
    size_t peak = 0;
    for (size_t i = 1; i < len; i++)
        if (M[i] > M[peak]) peak = i;
    *timing_idx = peak;
    return 0;
}
