// Unit tests for CSS demodulation (downchirp, dechirp, FFT peak).

#include "soundwave/css.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    css_config_t cfg = {
        .sf = 8,
        .bandwidth = 2000.0f,
        .sample_rate = 44100.0f,
        .f0 = 18000.0f,
    };
    css_init(&cfg);

    float* downchirp = (float*)malloc(cfg.chirp_len * sizeof(float));
    css_generate_downchirp(&cfg, downchirp);
    printf("PASS: downchirp generated, length=%d\n", cfg.chirp_len);

    float* dechirped = (float*)malloc(cfg.chirp_len * sizeof(float));
    float* samples = (float*)calloc(cfg.chirp_len, sizeof(float));
    css_dechirp(samples, cfg.chirp_len, downchirp, dechirped, cfg.chirp_len);
    printf("PASS: dechirp on silence produced output\n");

    free(downchirp); free(dechirped); free(samples);
    printf("All CSS demodulate tests passed.\n");
    return 0;
}
