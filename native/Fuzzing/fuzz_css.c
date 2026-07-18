// Fuzz target: CSS demodulator. Feed random float samples.

#include "soundwave/css.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
    if (Size < 4) return 0;
    css_config_t cfg = {
        .sf = 8,
        .bandwidth = 2000.0f,
        .sample_rate = 44100.0f,
        .f0 = 18000.0f,
    };
    css_init(&cfg);

    size_t float_count = Size / 4;
    float* samples = (float*)malloc(float_count * sizeof(float));
    memcpy(samples, Data, float_count * 4);

    size_t out_len = 0;
    uint8_t* bits = css_demodulate_frame(samples, float_count, &cfg, &out_len);
    free(bits);
    free(samples);
    return 0;
}
