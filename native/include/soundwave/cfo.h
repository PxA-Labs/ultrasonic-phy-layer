// Carrier Frequency Offset (CFO) estimation and correction.
// Uses Schmidl-Cox algorithm with autocorrelation of repeated training symbols.

#ifndef SOUNDWAVE_CFO_H
#define SOUNDWAVE_CFO_H

#include <stddef.h>

// Convert real passband to complex analytic signal via Hilbert FFT.
void sync_real_to_analytic(const float* real, size_t len,
                           float* analytic_real, float* analytic_imag);

// Schmidl-Cox CFO estimation: Delta_f = fs/(2pi*N) * angle(sum y*[n] * y[n+N]).
// Returns CFO in Hz. Estimation range: |CFO| <= fs/(2*N).
float sync_schmidl_cox_cfo(const float* y, size_t len, int N, float fs);

// Generate CFO correction phasor: corr[n] = exp(-j*2pi*Delta_f/fs*n).
void sync_correction_phasor(float cfo, float fs, size_t len,
                            float* corr_real, float* corr_imag);

// Apply CFO correction: out[n] = real((y_real[n] + j*y_imag[n]) * corr[n]).
void sync_apply_cfo_correction(const float* y_real, const float* y_imag,
                               size_t len, float cfo, float fs,
                               float* out_real);

// Timing metric: M(d) = |P(d)|^2 / R(d)^2 (Schmidl-Cox timing).
void sync_schmidl_cox_timing(const float* y, size_t len, int N, float* M);
int  sync_find_timing_peak(const float* M, size_t len, size_t* timing_idx);

#endif // SOUNDWAVE_CFO_H
