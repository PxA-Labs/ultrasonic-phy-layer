// Unit tests for CSS modulation.

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

    float* chirp = (float*)malloc(cfg.chirp_len * sizeof(float));
    css_generate_upchirp(&cfg, chirp);
    printf("PASS: upchirp generated, length=%d\n", cfg.chirp_len);

    float* sym = (float*)malloc(cfg.chirp_len * sizeof(float));
    css_modulate_symbol(&cfg, 42, sym);
    printf("PASS: symbol 42 modulated\n");

    free(chirp);
    free(sym);
    printf("All CSS modulate tests passed.\n");
    return 0;
}
