// Zero-Forcing and MMSE frequency-domain equalizers.
// References: MATHEMATICAL_MODEL.md equations 21-22.

#include "soundwave/equalizer.h"
#include <math.h>

void equalize_zf(const kiss_fft_cpx* Y, const kiss_fft_cpx* H,
                 const int* data_indices, int num_data, kiss_fft_cpx* X_hat) {
    for (int i = 0; i < num_data; i++) {
        int k = data_indices[i];
        float mag2 = H[k].r * H[k].r + H[k].i * H[k].i;
        if (mag2 > 1e-12f) {
            float inv = 1.0f / mag2;
            X_hat[i].r = (Y[k].r * H[k].r + Y[k].i * H[k].i) * inv;
            X_hat[i].i = (Y[k].i * H[k].r - Y[k].r * H[k].i) * inv;
        } else {
            X_hat[i].r = X_hat[i].i = 0.0f;
        }
    }
}

void equalize_mmse(const kiss_fft_cpx* Y, const kiss_fft_cpx* H,
                   const int* data_indices, int num_data,
                   float inv_snr, kiss_fft_cpx* X_hat) {
    for (int i = 0; i < num_data; i++) {
        int k = data_indices[i];
        float mag2 = H[k].r * H[k].r + H[k].i * H[k].i;
        float denom = mag2 + inv_snr;
        if (denom > 1e-12f) {
            X_hat[i].r = (Y[k].r * H[k].r + Y[k].i * H[k].i) / denom;
            X_hat[i].i = (Y[k].i * H[k].r - Y[k].r * H[k].i) / denom;
        } else {
            X_hat[i].r = X_hat[i].i = 0.0f;
        }
    }
}

int demap_data(const kiss_fft_cpx* X_hat, int num_data, int modulation,
               uint8_t* bits, size_t* num_bits) {
    size_t bit_pos = 0;
    for (int i = 0; i < num_data; i++) {
        float r = X_hat[i].r;
        if (modulation == 0) { // BPSK
            bits[bit_pos / 8] |= (r > 0.0f) ? (1 << (bit_pos % 8)) : 0;
            bit_pos++;
        }
        // QPSK and 16QAM: TODO
    }
    *num_bits = bit_pos;
    return 0;
}
