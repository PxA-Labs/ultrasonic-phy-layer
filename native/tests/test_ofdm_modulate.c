// Unit tests for OFDM modulation.
// References: MATHEMATICAL_MODEL.md section 2.2.2.

#include "soundwave/ofdm.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <math.h>

int main(void) {
    printf("Running test_ofdm_modulate...\n");

    // --- Test 1: BPSK mapping constellation points ---
    kiss_fft_cpx bpsk_sym0, bpsk_sym1;
    bpsk_map(0, &bpsk_sym0);
    bpsk_map(1, &bpsk_sym1);
    assert(fabsf(bpsk_sym0.r - (-1.0f)) <= 1e-6f && fabsf(bpsk_sym0.i) <= 1e-6f);
    assert(fabsf(bpsk_sym1.r - 1.0f) <= 1e-6f && fabsf(bpsk_sym1.i) <= 1e-6f);

    assert(bpsk_demap(bpsk_sym0) == 0);
    assert(bpsk_demap(bpsk_sym1) == 1);
    printf("PASS: BPSK mapping constellation verified.\n");

    // --- Test 2: QPSK mapping constellation points & Gray code ---
    kiss_fft_cpx qpsk_sym[4];
    float val = 0.70710678f;
    qpsk_map(0, &qpsk_sym[0]); // 00
    qpsk_map(1, &qpsk_sym[1]); // 01
    qpsk_map(2, &qpsk_sym[2]); // 10
    qpsk_map(3, &qpsk_sym[3]); // 11

    // Check positions
    assert(fabsf(qpsk_sym[0].r - val) <= 1e-6f && fabsf(qpsk_sym[0].i - val) <= 1e-6f);
    assert(fabsf(qpsk_sym[1].r - (-val)) <= 1e-6f && fabsf(qpsk_sym[1].i - val) <= 1e-6f);
    assert(fabsf(qpsk_sym[2].r - val) <= 1e-6f && fabsf(qpsk_sym[2].i - (-val)) <= 1e-6f);
    assert(fabsf(qpsk_sym[3].r - (-val)) <= 1e-6f && fabsf(qpsk_sym[3].i - (-val)) <= 1e-6f);

    // Check demapping
    assert(qpsk_demap_hard(qpsk_sym[0]) == 0);
    assert(qpsk_demap_hard(qpsk_sym[1]) == 1);
    assert(qpsk_demap_hard(qpsk_sym[2]) == 2);
    assert(qpsk_demap_hard(qpsk_sym[3]) == 3);
    printf("PASS: QPSK constellation mapping and Gray-code hard demapping verified.\n");

    // --- Test 3: CP copy validation ---
    ofdm_config_t cfg = {
        .num_subcarriers = 64,
        .cp_length = 16,
        .modulation = 1,
        .num_pilots = 8,
        .pilot_boost = 1.0f,
        .pilot_spacing = 8,
    };
    ofdm_init(&cfg);

    int N = cfg.num_subcarriers;
    int cp = cfg.cp_length;
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    X[10].r = 1.0f;
    X[20].i = 1.0f;

    float* time = (float*)malloc((N + cp) * sizeof(float));
    ofdm_modulate_symbol(&cfg, X, time);

    // CP check: first cp samples must be equal to last cp samples of length N symbol
    for (int n = 0; n < cp; n++) {
        assert(fabsf(time[n] - time[N + n]) <= 1e-6f);
    }
    printf("PASS: Cyclic Prefix copy validation verified.\n");

    // --- Test 4: DFT -> IDFT round-trip MSE validation ---
    kiss_fft_cpx* Y = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    ofdm_dft_demodulate(time, N, cp, Y);

    for (int k = 0; k <= N / 2; k++) {
        float diff_r = fabsf(X[k].r - Y[k].r);
        float diff_i = fabsf(X[k].i - Y[k].i);
        if (diff_r > 1e-5f || diff_i > 1e-5f) {
            printf("MISMATCH at k = %d: X = %f + j*%f, Y = %f + j*%f (diff_r = %f, diff_i = %f)\n",
                   k, X[k].r, X[k].i, Y[k].r, Y[k].i, diff_r, diff_i);
        }
        assert(diff_r <= 1e-5f);
        assert(diff_i <= 1e-5f);
    }
    printf("PASS: DFT -> IDFT round-trip MSE verified.\n");

    // --- Test 5: Subcarrier orthogonality validation ---
    // If we transmit on subcarrier k, the received DFT at subcarrier l (l != k) should be 0.
    for (int k = 0; k <= N / 2; k++) {
        if (k != 10 && k != 20) {
            assert(fabsf(Y[k].r) <= 1e-5f);
            assert(fabsf(Y[k].i) <= 1e-5f);
        }
    }
    printf("PASS: Subcarrier orthogonality verified.\n");

    free(X);
    free(time);
    free(Y);
    printf("All OFDM modulate tests passed successfully!\n");
    return 0;
}
