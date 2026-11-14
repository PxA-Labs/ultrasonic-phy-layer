// Carrier Frequency Offset (CFO) estimation and correction.
// Uses Schmidl-Cox algorithm with autocorrelation of repeated training symbols.

#ifndef SOUNDWAVE_CFO_H
#define SOUNDWAVE_CFO_H

#include <stddef.h>

// Convert real passband to complex analytic signal via Hilbert FFT.
// Returns 0 on success, -1 on bad arguments or allocation failure.
int  sync_real_to_analytic(const float* real, size_t len,
                           float* analytic_real, float* analytic_imag);

// Schmidl-Cox CFO estimation: Delta_f = fs/(2pi*N) * angle(sum y*[n] * y[n+N]).
// Returns CFO in Hz. Estimation range: |CFO| <= fs/(2*N).
// Returns 0.0f when no estimate is possible (N <= 0, len < 2N, bad fs).
float sync_schmidl_cox_cfo(const float* y, size_t len, int N, float fs);

// Generate CFO correction phasor: corr[n] = exp(-j*2pi*Delta_f/fs*n).
void sync_correction_phasor(float cfo, float fs, size_t len,
                            float* corr_real, float* corr_imag);

// Apply CFO correction: out[n] = real((y_real[n] + j*y_imag[n]) * corr[n]).
void sync_apply_cfo_correction(const float* y_real, const float* y_imag,
                               size_t len, float cfo, float fs,
                               float* out_real);

// Schmidl-Cox timing is computed on the analytic signal in
// sync_detect_frame() (sync_frame.c); fine timing in ofdm_refine_timing().

#endif // SOUNDWAVE_CFO_H
