// FFT (overlap-save) cross-correlation must match the direct matched filter.
#include "soundwave/sync.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "CHECK failed: %s (%s:%d)\n", #c, __FILE__, __LINE__); exit(1); } } while (0)

static unsigned rng = 12345u;
static float frand(void) { rng = rng * 1103515245u + 12345u; return ((rng >> 8) & 0xFFFF) / 32768.0f - 1.0f; }

int main(void) {
    const size_t cases[][2] = {{100, 1}, {100, 100}, {1000, 17}, {5000, 882},
                               {20000, 2205}, {4097, 1024}, {300000, 4800}};
    for (size_t c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        size_t yl = cases[c][0], sl = cases[c][1], ol = yl - sl + 1;
        float* y = malloc(yl * sizeof(float));
        float* s = malloc(sl * sizeof(float));
        float* a = malloc(ol * sizeof(float));
        float* b = malloc(ol * sizeof(float));
        CHECK(y && s && a && b);
        for (size_t i = 0; i < yl; i++) y[i] = frand();
        for (size_t i = 0; i < sl; i++) s[i] = frand();
        sync_matched_filter(y, yl, s, sl, a);
        CHECK(sync_xcorr_fft(y, yl, s, sl, b) == 0);
        // Tolerance relative to the correlation scale (sqrt(sl) for unit noise).
        double tol = 1e-3 * sqrt((double)sl) + 1e-4, worst = 0.0;
        for (size_t m = 0; m < ol; m++) {
            double d = fabs((double)a[m] - (double)b[m]);
            if (d > worst) worst = d;
        }
        printf("y=%zu s=%zu max|direct-fft|=%.2e (tol %.2e)\n", yl, sl, worst, tol);
        CHECK(worst <= tol);
        free(y); free(s); free(a); free(b);
    }
    float y[4] = {1, 2, 3, 4}, s[8] = {0}, r[4];
    CHECK(sync_xcorr_fft(y, 4, s, 8, r) == -1); // template longer than input
    CHECK(sync_xcorr_fft(NULL, 4, s, 1, r) == -1);
    printf("PASS: FFT cross-correlation matches direct form\n");
    return 0;
}
