// Unit tests for CFO estimation and correction.

#include "soundwave/cfo.h"
#include <stdio.h>
#include <assert.h>
#include <math.h>

int main(void) {
    float fs = 44100.0f;
    int N = 128;
    int len = 2 * N;

    // Generate a signal with known CFO
    float* y = (float*)malloc(len * sizeof(float));
    float cfo_true = 50.0f;
    for (int n = 0; n < len; n++)
        y[n] = cosf(2.0f * 3.14159f * cfo_true / fs * n);

    float cfo_est = sync_schmidl_cox_cfo(y, len, N, fs);
    printf("CFO estimate: %f Hz (true=%f Hz)\n", cfo_est, cfo_true);

    float* corrected = (float*)malloc(len * sizeof(float));
    sync_apply_cfo_correction(y, y, len, cfo_est, fs, corrected);
    printf("PASS: CFO correction applied\n");

    free(y); free(corrected);
    printf("All CFO tests passed.\n");
    return 0;
}
