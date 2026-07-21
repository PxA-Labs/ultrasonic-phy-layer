#ifndef BENCH_UTIL_H
#define BENCH_UTIL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <stdint.h>

#if defined(_WIN32) || defined(_WIN64)
    #include <windows.h>
    typedef struct { LARGE_INTEGER start; LARGE_INTEGER end; LARGE_INTEGER freq; } bench_timer;
    static bench_timer bench_now(void) {
        bench_timer t;
        QueryPerformanceFrequency(&t.freq);
        QueryPerformanceCounter(&t.start);
        return t;
    }
    static double bench_elapsed_us(bench_timer* t) {
        QueryPerformanceCounter(&t->end);
        return (double)(t->end.QuadPart - t->start.QuadPart) * 1e6 / (double)t->freq.QuadPart;
    }
#else
    typedef struct { struct timespec start; struct timespec end; } bench_timer;
    static bench_timer bench_now(void) {
        bench_timer t;
        clock_gettime(CLOCK_MONOTONIC, &t.start);
        return t;
    }
    static double bench_elapsed_us(bench_timer* t) {
        clock_gettime(CLOCK_MONOTONIC, &t->end);
        return (t->end.tv_sec - t->start.tv_sec) * 1e6 +
               (t->end.tv_nsec - t->start.tv_nsec) / 1e3;
    }
#endif

static void bench_report(const char* name, double elapsed_us, int64_t iterations) {
    double per_op = elapsed_us / (double)iterations;
    printf("{\"name\":\"%s\",\"value\":%.3f,\"unit\":\"us\"}\n",
           name, per_op);
}

#define BENCH_BLOCK(NAME, ITERATIONS, BODY) do {                    \
    bench_timer _bt = bench_now();                                  \
    for (int64_t _i = 0; _i < (ITERATIONS); _i++) { BODY; }        \
    double _elapsed = bench_elapsed_us(&_bt);                       \
    bench_report((NAME), _elapsed, (ITERATIONS));                   \
} while(0)

#endif
