// Unit tests for DSP paths the loopback tests do not reach (issue #36):
// the Reed-Solomon decoder stages and its failure guarantees, OFDM frame
// buffer negotiation and constellation mapping, CSS frame sync with default
// parameters, pilot SNR estimation and the FFI allocation helpers.

#include "soundwave_api.h"
#include "soundwave/chanest.h"
#include "soundwave/css.h"
#include "soundwave/ofdm.h"
#include "soundwave/rs.h"
#include "soundwave/sync.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Always-on check (Release builds define NDEBUG and would drop assert()).
#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "CHECK failed: %s (%s:%d)\n", #cond, __FILE__,     \
                    __LINE__);                                                 \
            exit(1);                                                           \
        }                                                                      \
    } while (0)

// Exported for dart:ffi (src/api/ffi_helpers.c) but not in the public header.
SW_API float* sw_alloc_float(int n);
SW_API double* sw_alloc_double(int n);
SW_API uint8_t* sw_alloc_uint8(int n);
SW_API void sw_free(void* ptr);

static uint32_t rng_state = 12345u;
static uint32_t rng(void) {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state >> 8;
}

/* ------------------------------------------------------------------------ */
/* Reed-Solomon decoder                                                     */
/* ------------------------------------------------------------------------ */

static void make_codeword(uint8_t* cw, size_t k, size_t n) {
    for (size_t i = 0; i < k; i++) cw[i] = (uint8_t)rng();
    rs_encode(cw, k, cw + k, n);
}

// Flips `count` distinct positions of cw[0..n) with non-zero error values.
static void corrupt(uint8_t* cw, size_t n, int count) {
    uint8_t hit[255] = {0};
    for (int e = 0; e < count;) {
        size_t p = rng() % n;
        if (hit[p]) continue;
        hit[p] = 1;
        cw[p] ^= (uint8_t)(1 + rng() % 255);
        e++;
    }
}

// Syndromes -> Berlekamp-Massey -> Chien -> Forney on RS(255,223), checked
// against the known error positions and values.
static void test_rs_decoder_stages(void) {
    uint8_t cw[255], S[32];
    make_codeword(cw, 223, 255);

    rs_compute_syndromes(cw, 255, S);
    for (int i = 0; i < 32; i++) CHECK(S[i] == 0); // valid codeword

    const int pos[3] = {10, 100, 250};
    const uint8_t val[3] = {0x11, 0x22, 0x33};
    uint8_t rx[255];
    memcpy(rx, cw, 255);
    for (int i = 0; i < 3; i++) rx[pos[i]] ^= val[i];

    rs_compute_syndromes(rx, 255, S);
    int nonzero = 0;
    for (int i = 0; i < 32; i++) nonzero |= S[i];
    CHECK(nonzero);

    uint8_t lambda[65] = {0}, omega[65] = {0};
    CHECK(rs_berlekamp_massey(S, lambda, omega) == 3);
    CHECK(lambda[0] == 1);

    int found[64] = {0}, count = -1;
    rs_chien_search(lambda, 3, found, &count);
    CHECK(count == 3);
    for (int i = 0; i < 3; i++) CHECK(found[i] == pos[i]); // ascending

    uint8_t mag[64] = {0};
    rs_forney(omega, lambda, found, count, mag);
    for (int i = 0; i < 3; i++) CHECK(mag[i] == val[i]);

    // Degenerate Chien inputs.
    count = 99;
    rs_chien_search(lambda, 0, found, &count);
    CHECK(count == 0);
    count = 99;
    rs_chien_search(NULL, 3, found, &count);
    CHECK(count == 0);
    rs_compute_syndromes(NULL, 255, S); // must not crash
    printf("PASS: RS stages find the exact error positions and values\n");
}

// A failed decode must report -1 and leave the received word untouched (the
// caller may still use or retransmit it); it must never "correct" it into a
// different codeword.
static void test_rs_failure_leaves_input_unchanged(void) {
    const struct { size_t n, nsym; int errors; } cases[] = {
        {255, 32, 17}, {255, 32, 24}, {255, 32, 60}, {100, 32, 17},
        {63, 16, 9}, {40, 32, 20},
    };
    for (size_t c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        for (int trial = 0; trial < 10; trial++) {
            uint8_t cw[255], rx[255], before[255];
            make_codeword(cw, cases[c].n - cases[c].nsym, cases[c].n);
            memcpy(rx, cw, cases[c].n);
            corrupt(rx, cases[c].n, cases[c].errors);
            memcpy(before, rx, cases[c].n);
            int rc = rs_decode_nsym(rx, cases[c].n, cases[c].nsym);
            if (rc != -1 || memcmp(rx, before, cases[c].n) != 0) {
                fprintf(stderr, "n=%zu nsym=%zu errors=%d trial=%d rc=%d\n",
                        cases[c].n, cases[c].nsym, cases[c].errors, trial, rc);
                exit(1);
            }
        }
    }
    printf("PASS: uncorrectable words are rejected and left unchanged\n");
}

static void test_rs_shortened_and_arguments(void) {
    // RS(40,8): heavily shortened, still corrects t = 16.
    uint8_t cw[40], rx[40];
    make_codeword(cw, 8, 40);
    memcpy(rx, cw, 40);
    corrupt(rx, 40, 16);
    CHECK(rs_decode_nsym(rx, 40, 32) == 16);
    CHECK(memcmp(rx, cw, 40) == 0);
    CHECK(rs_decode_nsym(rx, 40, 32) == 0); // clean now

    CHECK(rs_decode_nsym(NULL, 40, 32) == -1);
    CHECK(rs_decode_nsym(rx, 0, 32) == -1);
    CHECK(rs_decode_nsym(rx, 256, 32) == -1);
    CHECK(rs_decode_nsym(rx, 40, 1) == -1);
    CHECK(rs_decode_nsym(rx, 40, 65) == -1);
    CHECK(rs_decode_nsym(rx, 40, 40) == -1); // no data symbols left
    uint8_t big[255] = {0};
    CHECK(rs_decode_nsym(big, 255, 65) == -1);
    CHECK(rs_decode(NULL, 255) == -1);
    CHECK(rs_decode(big, 0) == -1);
    CHECK(rs_decode(big, 256) == -1);
    printf("PASS: shortened RS(40,8) and decoder argument checks\n");
}

/* ------------------------------------------------------------------------ */
/* OFDM modulator                                                           */
/* ------------------------------------------------------------------------ */

static void test_constellation_maps(void) {
    for (uint8_t d = 0; d < 4; d++) {
        kiss_fft_cpx x;
        qpsk_map(d, &x);
        CHECK(fabsf(x.r * x.r + x.i * x.i - 1.0f) < 1e-5f); // unit energy
        CHECK(qpsk_demap_hard(x) == d);
    }
    for (int b = 0; b < 2; b++) {
        kiss_fft_cpx x;
        bpsk_map(b, &x);
        CHECK(fabsf(fabsf(x.r) - 1.0f) < 1e-6f && x.i == 0.0f);
        CHECK(bpsk_demap(x) == b);
    }
    printf("PASS: BPSK/QPSK map -> hard demap round trip, unit energy\n");
}

static void test_ofdm_frame_buffer_negotiation(void) {
    ofdm_config_t cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.num_subcarriers = 256;
    cfg.cp_length = 32;
    cfg.modulation = 1;
    ofdm_init(&cfg);

    int idx_d[256], idx_p[256], idx_n[256], nd = 0, np = 0, nn = 0;
    ofdm_allocate_subcarriers(256, idx_d, idx_p, idx_n, &nd, &np, &nn);
    CHECK(nd > 0 && np > 0);
    const size_t sym = 256 + 32;
    const size_t bits = 64 * 8;
    const size_t bps = (size_t)nd * 2;
    const size_t total = (2 + (bits + bps - 1) / bps) * sym;

    uint8_t payload[64];
    for (int i = 0; i < 64; i++) payload[i] = (uint8_t)rng();
    float* out = (float*)malloc(total * sizeof(float));
    CHECK(out != NULL);

    size_t len = 2 * sym - 1; // not even room for the preamble
    CHECK(ofdm_modulate_frame(&cfg, payload, bits, out, &len) == SW_ERR_OVERFLOW);
    CHECK(len == 0);
    len = total - 1; // preamble fits, data does not: required size reported
    CHECK(ofdm_modulate_frame(&cfg, payload, bits, out, &len) == SW_ERR_OVERFLOW);
    CHECK(len == total);
    len = total;
    CHECK(ofdm_modulate_frame(&cfg, payload, bits, out, &len) == SW_OK);
    CHECK(len == total);
    double energy = 0.0;
    for (size_t i = 0; i < total; i++) {
        CHECK(isfinite(out[i]));
        energy += (double)out[i] * out[i];
    }
    CHECK(energy > 0.0);

    // No payload: just the two preamble symbols.
    len = total;
    CHECK(ofdm_modulate_frame(&cfg, payload, 0, out, &len) == SW_OK);
    CHECK(len == 2 * sym);

    // Invalid configurations and arguments.
    ofdm_config_t bad = cfg;
    bad.num_subcarriers = 100;
    len = total;
    CHECK(ofdm_modulate_frame(&bad, payload, bits, out, &len) == SW_ERR_BAD_PARAM);
    bad = cfg; bad.num_subcarriers = 8;
    CHECK(ofdm_modulate_frame(&bad, payload, bits, out, &len) == SW_ERR_BAD_PARAM);
    bad = cfg; bad.cp_length = -1;
    CHECK(ofdm_modulate_frame(&bad, payload, bits, out, &len) == SW_ERR_BAD_PARAM);
    bad = cfg; bad.cp_length = 257;
    CHECK(ofdm_modulate_frame(&bad, payload, bits, out, &len) == SW_ERR_BAD_PARAM);
    CHECK(ofdm_modulate_frame(NULL, payload, bits, out, &len) == SW_ERR_BAD_PARAM);
    CHECK(ofdm_modulate_frame(&cfg, NULL, bits, out, &len) == SW_ERR_BAD_PARAM);
    CHECK(ofdm_modulate_frame(&cfg, payload, bits, NULL, &len) == SW_ERR_BAD_PARAM);
    CHECK(ofdm_modulate_frame(&cfg, payload, bits, out, NULL) == SW_ERR_BAD_PARAM);
    free(out);
    printf("PASS: ofdm_modulate_frame negotiates buffer sizes and validates config\n");
}

/* ------------------------------------------------------------------------ */
/* Frame synchronisation                                                    */
/* ------------------------------------------------------------------------ */

// CSS preamble (8 base up-chirps + 2 down-chirps) from the documented
// defaults: SF8, 19 kHz centre, 2 kHz band, 44.1 kHz -> 22 samples per chip,
// N = 256 * 22 = 5632 samples per chirp. A zeroed sync config must fall back
// to exactly these values. Every lag is scored on all 10 preamble chirps, so
// a preamble right at the end of the buffer is located as accurately as one
// followed by a frame body.
static void test_css_sync_defaults(void) {
    sw_config_t mc;
    memset(&mc, 0, sizeof mc);
    const uint8_t body[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    sw_signal frame = css_modulate(body, 32, mc);
    css_geometry_t g;
    CHECK(css_geometry(&mc, &g) == 0 && g.N == 5632 && g.sf == 8 && g.D == 22);
    const size_t N = (size_t)g.N, offset = 1500;
    CHECK(frame.data && frame.length == (10 + 4) * N);

    const size_t lens[2] = {offset + frame.length + 3000, // with body and tail
                            offset + 10 * N};             // ends with the preamble
    for (int t = 0; t < 2; t++) {
        const size_t len = lens[t];
        float* x = (float*)malloc(len * sizeof(float));
        CHECK(x != NULL);
        for (size_t i = 0; i < len; i++)
            x[i] = 0.01f * ((float)(rng() % 2001) / 1000.0f - 1.0f);
        for (size_t i = 0; i < frame.length && offset + i < len; i++) x[offset + i] += frame.data[i];

        sync_config_t cfg;
        memset(&cfg, 0, sizeof cfg); // mode 0 (CSS), every parameter defaulted
        size_t start = 0;
        float snr = 0.0f;
        CHECK(sync_detect_frame(x, len, &cfg, &start, &snr) == 1);
        CHECK(start + 1 >= offset && start <= offset + 1);
        CHECK(isfinite(snr) && snr > 10.0f);
        // One sample short of the full preamble: not a frame yet.
        CHECK(sync_detect_frame(x, offset + 10 * N - 1, &cfg, &start, &snr) == 0);

        if (t == 0) {
            // Too short for a 10-symbol preamble, bad arguments, unknown mode.
            CHECK(sync_detect_frame(x, 10 * N - 1, &cfg, &start, &snr) == 0);
            CHECK(sync_detect_frame(NULL, len, &cfg, &start, &snr) == 0);
            CHECK(sync_detect_frame(x, len, NULL, &start, &snr) == 0);
            CHECK(sync_detect_frame(x, len, &cfg, NULL, &snr) == 0);
            CHECK(sync_detect_frame(x, len, &cfg, &start, NULL) == 0);
            sync_config_t other = cfg;
            other.sf = 11; // unsupported spreading factor
            CHECK(sync_detect_frame(x, len, &other, &start, &snr) == 0);
            other = cfg;
            other.mode = 2;
            CHECK(sync_detect_frame(x, len, &other, &start, &snr) == 0);
            // OFDM mode needs two symbol periods.
            other.mode = 1;
            other.matched_filter_len = 0; // default 256 + 32
            CHECK(sync_detect_frame(x, 2 * (256 + 32) - 1, &other, &start, &snr) == 0);
        }
        free(x);
    }
    free(frame.data);
    printf("PASS: CSS frame sync with default parameters finds the preamble\n");
}

static void test_detect_preamble_threshold(void) {
    const float R[6] = {0.1f, 0.5f, 2.0f, 0.3f, 2.0f, 0.2f};
    size_t start = 99;
    // Peak 2.0 (first occurrence); detection requires peak^2 > threshold * noise.
    CHECK(sync_detect_preamble(R, 6, 3.0f, 1.0f, &start) == 1 && start == 2);
    start = 99;
    CHECK(sync_detect_preamble(R, 6, 4.0f, 1.0f, &start) == 0 && start == 99);
    CHECK(sync_detect_preamble(R, 0, 3.0f, 1.0f, &start) == 0);
    CHECK(sync_detect_preamble(NULL, 6, 3.0f, 1.0f, &start) == 0);
    CHECK(sync_detect_preamble(R, 6, 3.0f, 1.0f, NULL) == 0);
    printf("PASS: preamble threshold rule and first-peak selection\n");
}

/* ------------------------------------------------------------------------ */
/* Channel estimation SNR, FFI helpers                                      */
/* ------------------------------------------------------------------------ */

static void test_pilot_snr(void) {
    kiss_fft_cpx X[4] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
    kiss_fft_cpx H[4] = {{0.5f, 0.5f}, {1, 0}, {0, 2}, {1, -1}};
    kiss_fft_cpx Y[4];
    for (int i = 0; i < 4; i++) {
        Y[i].r = H[i].r * X[i].r - H[i].i * X[i].i;
        Y[i].i = H[i].r * X[i].i + H[i].i * X[i].r;
    }
    CHECK(chanest_estimate_snr(Y, X, H, 4) == 100.0f); // noiseless -> ceiling

    // Signal power sum |H|^2|X|^2 = 0.5 + 1 + 4 + 2 = 7.5; add noise of power
    // 0.0075 per pilot (total 0.03) -> SNR = 10 log10(7.5 / 0.03) = 23.98 dB.
    const float e = sqrtf(0.0075f);
    Y[0].r += e;
    Y[1].i -= e;
    Y[2].r -= e;
    Y[3].i += e;
    float snr = chanest_estimate_snr(Y, X, H, 4);
    CHECK(fabsf(snr - 10.0f * log10f(7.5f / 0.03f)) < 0.01f);
    printf("PASS: pilot SNR estimate (%.2f dB) matches the closed form\n", snr);
}

static void test_ffi_alloc_helpers(void) {
    float* f = sw_alloc_float(1000);
    double* d = sw_alloc_double(1000);
    uint8_t* b = sw_alloc_uint8(1000);
    CHECK(f && d && b);
    for (int i = 0; i < 1000; i++) CHECK(f[i] == 0.0f && d[i] == 0.0 && b[i] == 0);
    f[999] = 1.0f; // writable to the end
    d[999] = 1.0;
    b[999] = 1;
    sw_free(f);
    sw_free(d);
    sw_free(b);
    sw_free(NULL); // like free(NULL)
    printf("PASS: FFI allocation helpers return zeroed buffers\n");
}

int main(void) {
    rs_init_generator();
    test_rs_decoder_stages();
    test_rs_failure_leaves_input_unchanged();
    test_rs_shortened_and_arguments();
    test_constellation_maps();
    test_ofdm_frame_buffer_negotiation();
    test_css_sync_defaults();
    test_detect_preamble_threshold();
    test_pilot_snr();
    test_ffi_alloc_helpers();
    printf("All DSP path tests passed.\n");
    return 0;
}
