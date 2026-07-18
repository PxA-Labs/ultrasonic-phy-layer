#include "bench_util.h"
#include "kiss_fft.h"
#include "tools/kiss_fftr.h"

int main(void) {
    printf("[\n");
    int first = 1;

    for (int N = 256; N <= 2048; N *= 2) {
        kiss_fft_cfg cfg = kiss_fft_alloc(N, 0, NULL, NULL);
        kiss_fft_cpx* in = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
        kiss_fft_cpx* out = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
        char name[64];
        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "FFT_%d_complex", N);
            BENCH_BLOCK(name, 5000, { kiss_fft(cfg, in, out); });
        }
        free(in); free(out); free(cfg);
    }

    for (int N = 256; N <= 2048; N *= 2) {
        kiss_fftr_cfg cfg = kiss_fftr_alloc(N, 0, NULL, NULL);
        kiss_fft_scalar* in = (kiss_fft_scalar*)calloc(N, sizeof(kiss_fft_scalar));
        kiss_fft_cpx* out = (kiss_fft_cpx*)calloc(N / 2 + 1, sizeof(kiss_fft_cpx));
        char name[64];
        for (int trial = 0; trial < 3; trial++) {
            if (!first) printf(",\n"); first = 0;
            snprintf(name, sizeof(name), "FFT_%d_real", N);
            BENCH_BLOCK(name, 5000, { kiss_fftr(cfg, in, out); });
        }
        free(in); free(out); free(cfg);
    }

    printf("\n]\n");
    return 0;
}
