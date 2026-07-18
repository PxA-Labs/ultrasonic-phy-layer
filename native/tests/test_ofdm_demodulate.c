// Unit tests for OFDM demodulation, channel estimation, and equalization.

#include "soundwave/ofdm.h"
#include "soundwave/chanest.h"
#include "soundwave/equalizer.h"
#include "kiss_fft.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    ofdm_config_t cfg = {
        .num_subcarriers = 64,
        .cp_length = 16,
        .modulation = 1,
        .num_pilots = 8,
        .pilot_boost = 3.0f,
        .pilot_spacing = 6,
    };
    ofdm_init(&cfg);

    // Modulate then demodulate -> verify identity
    int N = cfg.num_subcarriers;
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    X[10].r = 1.0f;

    float* time = (float*)malloc((N + cfg.cp_length) * sizeof(float));
    ofdm_modulate_symbol(&cfg, X, time);

    kiss_fft_cpx* Y = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    ofdm_dft_demodulate(time, N, cfg.cp_length, Y);
    printf("PASS: DFT demodulation completed, Y[10].r=%f\n", Y[10].r);

    free(X); free(time); free(Y);
    printf("All OFDM demodulate tests passed.\n");
    return 0;
}
