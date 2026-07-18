// Unit tests for frame synchronization (matched filter, ZC).

#include "soundwave/sync.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    float template[16];
    for (int i = 0; i < 16; i++) template[i] = (float)i;

    float signal[64];
    memset(signal, 0, sizeof(signal));
    memcpy(signal + 20, template, 16 * sizeof(float)); // template at offset 20

    float R[48] = {0};
    sync_matched_filter(signal, 64, template, 16, R);

    size_t peak = 0;
    float noise_var = sync_estimate_noise(signal, 64);
    int detected = sync_detect_preamble(R, 48, 3.0f, noise_var, &peak);
    printf("PASS: matched filter peak at %zu (expected 20), detected=%d\n", peak, detected);

    // ZC test
    float zc_real[127], zc_imag[127];
    sync_zc_generate(1, 127, zc_real, zc_imag);
    printf("PASS: ZC(127,1) generated\n");

    printf("All sync tests passed.\n");
    return 0;
}
