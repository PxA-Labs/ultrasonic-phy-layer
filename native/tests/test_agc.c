// AGC tests (issue #92): level normalisation, convergence time, clamping,
// peak limiting, robustness to non-finite input, FFI handle validation and
// processing cost.

#include "soundwave/agc.h"
#include "soundwave_api.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "CHECK failed: %s (%s:%d)\n", #c, __FILE__, __LINE__); exit(1); } } while (0)

#define FS 44100.0f
#define TWO_PI 6.28318530718f

static float db(float x) { return 20.0f * log10f(x); }

// Linear chirp 18-20 kHz with peak amplitude amp, starting at sample offset.
static void chirp(float* x, size_t n, float amp, size_t phase0) {
    const float T = 0.02f, f0 = 18000.0f, B = 2000.0f;
    for (size_t i = 0; i < n; i++) {
        float t = fmodf((float)(i + phase0) / FS, T);
        x[i] = amp * cosf(TWO_PI * (f0 * t + 0.5f * B / T * t * t));
    }
}

static float rms(const float* x, size_t n) {
    double acc = 0.0;
    for (size_t i = 0; i < n; i++) acc += (double)x[i] * x[i];
    return (float)sqrt(acc / (double)n);
}

// Chirps 30 dB below, 10 dB below and 10 dB above the target come out within
// +-3 dB of the target once settled.
static void test_normalises_levels(void) {
    const float target = AGC_DEFAULT_TARGET_RMS;
    const float rel_db[] = {-30.0f, -10.0f, 10.0f};
    size_t n = (size_t)(1.0f * FS);
    float* x = malloc(n * sizeof(float));
    CHECK(x);
    for (int k = 0; k < 3; k++) {
        float in_rms = target * powf(10.0f, rel_db[k] / 20.0f);
        chirp(x, n, in_rms * sqrtf(2.0f), 0);
        agc_state_t* agc = agc_create(FS, target);
        CHECK(agc);
        CHECK(agc_process(agc, x, n) == 0);
        size_t settle = (size_t)(0.3f * FS);
        float out = rms(x + settle, n - settle);
        printf("input %+5.1f dB re target -> output %+5.2f dB re target (gain %+5.1f dB)\n",
               rel_db[k], db(out / target), agc_gain_db(agc));
        CHECK(fabsf(db(out / target)) <= 3.0f);
        agc_destroy(agc);
    }
    free(x);
    printf("PASS: AGC normalises -30/-10/+10 dB chirps to +-3 dB of target\n");
}

// After 0.5 s of near-silence (gain at maximum), a chirp's 10 ms output RMS
// enters +-3 dB of target within 200 ms of onset, and never exceeds full scale.
static void test_convergence_and_peak_limit(void) {
    const float target = AGC_DEFAULT_TARGET_RMS;
    size_t quiet = (size_t)(0.5f * FS), loud = (size_t)(0.5f * FS), n = quiet + loud;
    float* x = malloc(n * sizeof(float));
    CHECK(x);
    unsigned r = 1u;
    for (size_t i = 0; i < quiet; i++) {
        r = r * 1103515245u + 12345u;
        x[i] = 1e-4f * (((r >> 8) & 0xFFFF) / 32768.0f - 1.0f);
    }
    chirp(x + quiet, loud, 0.25f, 0); // -9 dB re target in RMS
    agc_state_t* agc = agc_create(FS, target);
    CHECK(agc);
    CHECK(agc_process(agc, x, quiet) == 0);
    // Silence drives the gain towards maximum at the 100 ms release rate:
    // after 0.5 s (5 time constants) it covers 1 - e^-5 = 99.3% of the way.
    CHECK(agc_gain(agc) > 0.98f * AGC_MAX_GAIN);
    CHECK(agc_process(agc, x + quiet, loud) == 0);

    float peak = 0.0f;
    for (size_t i = 0; i < n; i++) peak = fmaxf(peak, fabsf(x[i]));
    CHECK(peak <= AGC_PEAK_LIMIT + 1e-6f);

    size_t win = (size_t)(0.010f * FS), settled_at = 0;
    for (size_t w = quiet; w + win <= n; w += win) {
        if (fabsf(db(rms(x + w, win) / target)) <= 3.0f) {
            // must also stay settled from here on
            int stays = 1;
            for (size_t v = w; v + win <= n; v += win)
                if (fabsf(db(rms(x + v, win) / target)) > 3.0f) { stays = 0; break; }
            if (stays) { settled_at = w - quiet; break; }
        }
    }
    float ms = 1000.0f * (float)settled_at / FS;
    printf("converged within %.1f ms of onset; output peak %.3f\n", ms, peak);
    CHECK(settled_at > 0 && ms <= 200.0f);
    agc_destroy(agc);
    free(x);
    printf("PASS: converges within 200 ms and output never exceeds full scale\n");
}

static void test_gain_clamped(void) {
    float x[4410];
    agc_state_t* agc = agc_create(FS, AGC_DEFAULT_TARGET_RMS);
    CHECK(agc);
    memset(x, 0, sizeof x);
    for (int i = 0; i < 20; i++) CHECK(agc_process(agc, x, 4410) == 0);
    CHECK(agc_gain(agc) <= AGC_MAX_GAIN + 1e-4f);
    CHECK(fabsf(agc_gain_db(agc) - db(AGC_MAX_GAIN)) < 0.01f); // +32 dB
    for (int i = 0; i < 4410; i++) x[i] = (i % 2) ? 50.0f : -50.0f; // very loud
    for (int i = 0; i < 5; i++) CHECK(agc_process(agc, x, 4410) == 0);
    CHECK(agc_gain(agc) >= AGC_MIN_GAIN - 1e-6f);
    for (int i = 0; i < 4410; i++) CHECK(fabsf(x[i]) <= AGC_PEAK_LIMIT);
    agc_destroy(agc);
    printf("PASS: gain clamped to [-20, +32] dB and output to full scale\n");
}

static void test_non_finite_input(void) {
    float x[1000];
    agc_state_t* agc = agc_create(FS, AGC_DEFAULT_TARGET_RMS);
    CHECK(agc);
    chirp(x, 1000, 0.1f, 0);
    x[10] = NAN; x[20] = INFINITY; x[30] = -INFINITY;
    CHECK(agc_process(agc, x, 1000) == 0);
    for (int i = 0; i < 1000; i++) CHECK(isfinite(x[i]));
    CHECK(x[10] == 0.0f && x[20] == 0.0f && x[30] == 0.0f);
    CHECK(isfinite(agc_gain(agc)));
    CHECK(agc_process(agc, x, 0) == 0);
    CHECK(agc_process(agc, NULL, 4) == -1);
    CHECK(agc_process(NULL, x, 4) == -1);
    CHECK(agc_create(1000.0f, 0.25f) == NULL);
    CHECK(agc_create(FS, 0.0f) == NULL);
    CHECK(agc_create(FS, NAN) == NULL);
    agc_destroy(agc);
    agc_destroy(NULL);
    printf("PASS: non-finite samples dropped, bad arguments rejected\n");
}

static void test_ffi_handles(void) {
    void* h = NULL;
    float x[256], g = 0.0f;
    chirp(x, 256, 0.1f, 0);
    CHECK(sw_agc_create(44100, 0.0f, &h) == SW_OK && h); // 0 -> default target
    CHECK(sw_agc_process(h, x, 256) == SW_OK);
    CHECK(sw_agc_get_gain_db(h, &g) == SW_OK && isfinite(g));
    CHECK(sw_agc_reset(h) == SW_OK);
    CHECK(sw_agc_get_gain_db(h, &g) == SW_OK && fabsf(g) < 1e-4f);
    CHECK(sw_agc_destroy(h) == SW_OK);

    // Invalid handles are rejected, not dereferenced as AGC state.
    uint64_t garbage[4] = {0};
    CHECK(sw_agc_process(NULL, x, 256) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_process(garbage, x, 256) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_get_gain_db(garbage, &g) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_destroy(garbage) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(1000, 0.25f, &h) == SW_ERR_BAD_PARAM && h == NULL);
    CHECK(sw_agc_create(44100, 2.0f, &h) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(44100, 0.25f, NULL) == SW_ERR_BAD_PARAM);
    printf("PASS: FFI handle validation\n");
}

// Issue acceptance: < 1 ms per 10 ms chunk.
static void test_cost(void) {
    const size_t chunk = 441, chunks = 1000; // 10 s of audio
    float* x = malloc(chunk * sizeof(float));
    CHECK(x);
    agc_state_t* agc = agc_create(FS, AGC_DEFAULT_TARGET_RMS);
    CHECK(agc);
    clock_t t0 = clock();
    for (size_t c = 0; c < chunks; c++) {
        chirp(x, chunk, 0.1f, c * chunk);
        CHECK(agc_process(agc, x, chunk) == 0);
    }
    double per_chunk_ms = 1000.0 * (double)(clock() - t0) / CLOCKS_PER_SEC / (double)chunks;
    printf("cost: %.4f ms per 10 ms chunk (incl. test signal generation)\n", per_chunk_ms);
    CHECK(per_chunk_ms < 1.0);
    agc_destroy(agc);
    free(x);
    printf("PASS: processing cost below 1 ms per 10 ms chunk\n");
}

int main(void) {
    test_normalises_levels();
    test_convergence_and_peak_limit();
    test_gain_clamped();
    test_non_finite_input();
    test_ffi_handles();
    test_cost();
    printf("All AGC tests passed.\n");
    return 0;
}
