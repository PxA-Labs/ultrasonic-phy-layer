#ifndef SOUNDWAVE_EQUALIZER_H
#define SOUNDWAVE_EQUALIZER_H
// Frequency-domain equalizers — Zero-Forcing and MMSE.

#include <stddef.h>
#include <stdint.h>
#include "kiss_fft.h"

// Zero-Forcing equalizer: X_hat[k] = Y[k] / H[k]
void equalize_zf(const kiss_fft_cpx* Y, const kiss_fft_cpx* H,
                 const int* data_indices, int num_data, kiss_fft_cpx* X_hat);

// MMSE equalizer: X_hat[k] = Y[k] * conj(H[k]) / (|H[k]|^2 + 1/SNR)
void equalize_mmse(const kiss_fft_cpx* Y, const kiss_fft_cpx* H,
                   const int* data_indices, int num_data,
                   float inv_snr, kiss_fft_cpx* X_hat);

// Demap equalized complex symbols to bits.
int demap_data(const kiss_fft_cpx* X_hat, int num_data, int modulation,
               uint8_t* bits, size_t* num_bits);

#endif
