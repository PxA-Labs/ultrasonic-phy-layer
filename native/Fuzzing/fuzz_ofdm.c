// Fuzz target: OFDM demodulator. Feed random float samples.

#include "soundwave/ofdm.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
    if (Size < 8) return 0;
    ofdm_config_t cfg = {
        .num_subcarriers = 64,
        .cp_length = 16,
        .modulation = 1,
        .num_pilots = 8,
        .pilot_boost = 3.0f,
        .pilot_spacing = 6,
    };
    ofdm_init(&cfg);

    size_t float_count = Size / 4;
    float* samples = (float*)malloc(float_count * sizeof(float));
    memcpy(samples, Data, float_count * 4);

    size_t out_len = 0;
    uint8_t* bits = ofdm_demodulate_frame(samples, float_count, &cfg, &out_len);
    free(bits);
    free(samples);
    return 0;
}
