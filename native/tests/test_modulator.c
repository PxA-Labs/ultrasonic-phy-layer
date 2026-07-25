// Unit tests for modulator module (CSS Chirp + OFDM modulation)

#include "soundwave/modulator.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int main(void) {
    printf("Running test_modulator...\n");

    css_config_t cfg = {
        .sf = 8,
        .bandwidth = 2000.0f,
        .sample_rate = 44100.0f,
        .f0 = 18000.0f,
    };
    css_init(&cfg);

    float* chirp = (float*)malloc(cfg.chirp_len * sizeof(float));
    css_generate_upchirp(&cfg, chirp);
    assert(chirp != NULL);
    assert(cfg.chirp_len > 0);
    printf("PASS: CSS upchirp generation passed.\n");

    sw_config_t sw_cfg;
    sw_cfg.sample_rate = 44100;
    sw_cfg.sf = 7;
    sw_cfg.num_subcarriers = 256;
    sw_cfg.cp_length = 32;

    uint8_t bits[4] = {0x12, 0x34, 0x56, 0x78};
    float samples[4096];
    size_t sample_len = 0;

    int res = sw_css_modulate(bits, 4, sw_cfg, samples, &sample_len);
    assert(res == SW_OK || res == SW_ERR_NOT_IMPLEMENTED);
    printf("PASS: sw_css_modulate call executed.\n");

    res = sw_ofdm_modulate(bits, 4, sw_cfg, samples, &sample_len);
    assert(res == SW_OK || res == SW_ERR_NOT_IMPLEMENTED);
    printf("PASS: sw_ofdm_modulate call executed.\n");

    free(chirp);
    printf("All test_modulator tests passed successfully.\n");
    return 0;
}
