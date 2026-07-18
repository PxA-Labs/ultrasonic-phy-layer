#include "bench_util.h"
#include "soundwave/ofdm.h"
#include <stdlib.h>

int main(void) {
    printf("[\n");
    int first = 1;

    for (int N = 256; N <= 2048; N *= 2) {
        ofdm_config_t cfg = {
            .num_subcarriers = N,
            .cp_length = N / 4,
            .modulation = 1,
            .num_pilots = N / 8,
            .pilot_boost = 3.0f,
            .pilot_spacing = N / 32,
        };
        ofdm_init(&cfg);

        kiss_fft_cpx* X = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
        float* time = (float*)malloc((N + cfg.cp_length) * sizeof(float));
        kiss_fft_cpx* Y = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
        char name[64];

        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "OFDM_modulate_%d", N);
            BENCH_BLOCK(name, 2000, { ofdm_modulate_symbol(&cfg, X, time); });
        }

        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "OFDM_demodulate_%d", N);
            BENCH_BLOCK(name, 2000, { ofdm_dft_demodulate(time, N, cfg.cp_length, Y); });
        }

        free(X); free(time); free(Y);
    }

    printf("\n]\n");
    return 0;
}
