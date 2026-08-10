// Zero-Forcing and MMSE frequency-domain equalizers.
// References: MATHEMATICAL_MODEL.md equations 21-22.

#include "soundwave/equalizer.h"
#include "soundwave/ofdm.h"
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
    if (!X_hat || !bits || !num_bits) return -1;
    size_t bit_pos = 0;
    for (int i = 0; i < num_data; i++) {
        if (modulation == 0) { // BPSK
            int bit = (X_hat[i].r > 0.0f) ? 1 : 0;
            if (bit_pos % 8 == 0) {
                bits[bit_pos / 8] = 0;
            }
            bits[bit_pos / 8] |= (bit << (7 - (bit_pos % 8)));
            bit_pos++;
        } else if (modulation == 1) { // QPSK
            uint8_t dibit = qpsk_demap_hard(X_hat[i]);
            int bit1 = (dibit >> 1) & 1;
            int bit2 = dibit & 1;

            if (bit_pos % 8 == 0) bits[bit_pos / 8] = 0;
            bits[bit_pos / 8] |= (bit1 << (7 - (bit_pos % 8)));
            bit_pos++;

            if (bit_pos % 8 == 0) bits[bit_pos / 8] = 0;
            bits[bit_pos / 8] |= (bit2 << (7 - (bit_pos % 8)));
            bit_pos++;
        }
    }
    *num_bits = bit_pos;
    return 0;
}
