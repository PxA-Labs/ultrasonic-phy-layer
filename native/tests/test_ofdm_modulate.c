// Unit tests for OFDM modulation.

#include "soundwave/ofdm.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    ofdm_config_t cfg = {
        .num_subcarriers = 64,
        .cp_length = 16,
        .modulation = 1, // QPSK
        .num_pilots = 8,
        .pilot_boost = 3.0f,
        .pilot_spacing = 6,
    };
    ofdm_init(&cfg);

    float* time = (float*)malloc((cfg.num_subcarriers + cfg.cp_length) * sizeof(float));
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc(cfg.num_subcarriers, sizeof(kiss_fft_cpx));
    // Set one subcarrier
    X[10].r = 1.0f;
    ofdm_modulate_symbol(&cfg, X, time);
    printf("PASS: OFDM symbol modulated\n");

    free(time); free(X);
    printf("All OFDM modulate tests passed.\n");
    return 0;
}
