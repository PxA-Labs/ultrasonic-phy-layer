// Channel estimation — LS estimation at pilot positions and interpolation.
// References: MATHEMATICAL_MODEL.md equations 19-20.

#ifndef SOUNDWAVE_CHANEST_H
#define SOUNDWAVE_CHANEST_H

#include "kiss_fft.h"

// LS channel estimation: H_p[k] = Y[k] / X_p[k] at pilot indices.
void chanest_ls(const kiss_fft_cpx* Y, const kiss_fft_cpx* X_p,
                const int* pilot_indices, int num_pilots, kiss_fft_cpx* H_p);

// Linear interpolation of channel estimates across all subcarriers.
void chanest_linear_interp(const kiss_fft_cpx* H_p, const int* pilot_indices,
                           int num_pilots, int N, kiss_fft_cpx* H);

// Estimate SNR from pilot symbols: SNR_dB = 10*log10(P_signal / P_noise).
float chanest_estimate_snr(const kiss_fft_cpx* Y, const kiss_fft_cpx* X_p,
                           const kiss_fft_cpx* H_p, int num_pilots);

#endif // SOUNDWAVE_CHANEST_H
