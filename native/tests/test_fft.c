// Unit tests for FFT accuracy validation using kiss_fft

#include "kiss_fft.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>

int main(void) {
    printf("Running test_fft...\n");

    int nfft = 256;
    kiss_fft_cfg cfg = kiss_fft_alloc(nfft, 0, NULL, NULL);
    assert(cfg != NULL);

    kiss_fft_cpx in[256];
    kiss_fft_cpx out[256];

    // Impulse input
    for (int i = 0; i < nfft; i++) {
        in[i].r = (i == 0) ? 1.0f : 0.0f;
        in[i].i = 0.0f;
    }

    kiss_fft(cfg, in, out);

    // FFT of delta[n] is all 1s
    for (int i = 0; i < nfft; i++) {
        float mag = sqrtf(out[i].r * out[i].r + out[i].i * out[i].i);
        assert(fabsf(mag - 1.0f) < 1e-4f);
    }

    free(cfg);
    printf("PASS: KissFFT impulse response test passed.\n");

    printf("All test_fft tests passed successfully.\n");
    return 0;
}
