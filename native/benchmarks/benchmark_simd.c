#include "bench_util.h"
#include "soundwave/simd_util.h"
#include <stdio.h>
#include <stdlib.h>

#define DATA_SIZE 1024

int main(void) {
    printf("[\n");
    int first = 1;

    float* a = (float*)malloc(DATA_SIZE * sizeof(float));
    float* b = (float*)malloc(DATA_SIZE * sizeof(float));
    float* a_i = (float*)malloc(DATA_SIZE * sizeof(float));
    float* b_i = (float*)malloc(DATA_SIZE * sizeof(float));

    if (!a || !b || !a_i || !b_i) {
        free(a); free(b); free(a_i); free(b_i);
        return 1;
    }

    for (int i = 0; i < DATA_SIZE; i++) {
        a[i] = (float)rand() / (float)RAND_MAX;
        b[i] = (float)rand() / (float)RAND_MAX;
        a_i[i] = (float)rand() / (float)RAND_MAX;
        b_i[i] = (float)rand() / (float)RAND_MAX;
    }

    volatile float accum_r = 0.0f;
    volatile double accum_c = 0.0;

    // Benchmark real dot product
    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("DOT_PRODUCT_SCALAR", 50000, {
            accum_r += simd_dot_product_scalar(a, b, DATA_SIZE);
        });
    }

    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("DOT_PRODUCT_SIMD", 50000, {
            accum_r += simd_dot_product(a, b, DATA_SIZE);
        });
    }

    double r = 0.0;
    double i_val = 0.0;

    // Benchmark complex dot product
    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("COMPLEX_DOT_PRODUCT_SCALAR", 20000, {
            simd_complex_dot_product_scalar(a, a_i, b, b_i, DATA_SIZE, &r, &i_val);
            accum_c += r;
        });
    }

    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("COMPLEX_DOT_PRODUCT_SIMD", 20000, {
            simd_complex_dot_product(a, a_i, b, b_i, DATA_SIZE, &r, &i_val);
            accum_c += r;
        });
    }

    printf("\n]\n");

    // Print volatile accumulators to ensure compiler doesn't optimize away
    if (accum_r == 42.0f || accum_c == 42.0) {
        printf("/* debug: %f, %f */\n", accum_r, accum_c);
    }

    free(a);
    free(b);
    free(a_i);
    free(b_i);
    return 0;
}
