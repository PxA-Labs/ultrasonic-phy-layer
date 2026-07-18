#include "bench_util.h"
#include "soundwave/css.h"
#include <stdlib.h>

int main(void) {
    printf("[\n");
    int first = 1;

    int sf_values[] = {7, 8, 10, 12};
    for (int si = 0; si < 4; si++) {
        css_config_t cfg = {
            .sf = sf_values[si],
            .bandwidth = 2000.0f,
            .sample_rate = 44100.0f,
            .f0 = 18000.0f,
        };
        css_init(&cfg);

        float* chirp = (float*)malloc(cfg.chirp_len * sizeof(float));
        float* symbol = (float*)malloc(cfg.chirp_len * sizeof(float));
        char name[64];

        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "CSS_upchirp_SF%d", cfg.sf);
            BENCH_BLOCK(name, 1000, { css_generate_upchirp(&cfg, chirp); });
        }

        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "CSS_modulate_SF%d", cfg.sf);
            BENCH_BLOCK(name, 1000, { css_modulate_symbol(&cfg, 42, symbol); });
        }

        free(chirp); free(symbol);
    }

    printf("\n]\n");
    return 0;
}
