// Tests for sw_ofdm_equalized_symbols(): the equalized OFDM constellation
// points exposed for the Flutter constellation diagram (issue #71).
//
// Uses an explicit CHECK macro instead of assert() so the checks also run in
// Release builds (NDEBUG).

#include "soundwave_api.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                    \
        }                                                                  \
    } while (0)

#define MAX_SAMPLES (1u << 17)
#define MAX_POINTS 8192

static sw_config_t ofdm_config(int ofdm_modulation) {
    sw_config_t cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.sample_rate = 44100;
    cfg.modulation = 1;
    cfg.sf = 8;
    cfg.num_subcarriers = 256;
    cfg.cp_length = 32;
    cfg.num_pilots = 16;
    cfg.coding_rate = 0.5f;
    cfg.threshold = 3.0f;
    cfg.equalizer = 0;
    cfg.carrier_freq = 19000.0f;
    cfg.bandwidth = 2000.0f;
    cfg.symbol_duration = 0.02f;
    cfg.amplitude = 0.8f;
    cfg.ofdm_modulation = ofdm_modulation;
    return cfg;
}

static int bit_at(const uint8_t* bytes, size_t i) {
    return (bytes[i / 8] >> (7 - (i % 8))) & 1;
}

// Modulates payload; returns a malloc'd sample buffer (caller frees).
static float* modulate(const uint8_t* payload, size_t nbytes, sw_config_t cfg,
                       size_t* out_len) {
    float* samples = (float*)malloc(MAX_SAMPLES * sizeof(float));
    if (!samples) return NULL;
    size_t len = MAX_SAMPLES;
    int rc = sw_ofdm_modulate(payload, nbytes * 8, cfg, samples, &len);
    CHECK(rc == SW_OK);
    if (rc != SW_OK) {
        free(samples);
        return NULL;
    }
    *out_len = len;
    return samples;
}

// RMS error vector magnitude against the nearest ideal point (unit-energy
// reference constellation), as a fraction.
static double evm_rms(const float* iq, size_t n, int ofdm_modulation) {
    const double q = 0.70710678;
    double err = 0.0;
    for (size_t k = 0; k < n; k++) {
        double r = iq[2 * k], i = iq[2 * k + 1];
        double rr, ri;
        if (ofdm_modulation == 0) {
            rr = r >= 0 ? 1.0 : -1.0;
            ri = 0.0;
        } else {
            rr = r >= 0 ? q : -q;
            ri = i >= 0 ? q : -q;
        }
        err += (r - rr) * (r - rr) + (i - ri) * (i - ri);
    }
    return n ? sqrt(err / (double)n) : INFINITY;
}

static void test_qpsk_points_match_payload(void) {
    uint8_t payload[32];
    for (int i = 0; i < 32; i++) payload[i] = (uint8_t)(i * 37 + 11);
    sw_config_t cfg = ofdm_config(1);
    size_t n = 0;
    float* s = modulate(payload, sizeof payload, cfg, &n);
    if (!s) return;

    float* iq = (float*)malloc(2 * MAX_POINTS * sizeof(float));
    size_t count = MAX_POINTS;
    int rc = sw_ofdm_equalized_symbols(s, n, cfg, iq, &count);
    CHECK(rc == SW_OK);
    CHECK(count >= sizeof payload * 8 / 2); // 2 bits per QPSK point
    CHECK(count < MAX_POINTS);

    // Same number of points as the bit demodulator decides on.
    uint8_t bits[MAX_POINTS / 4];
    size_t bit_len = sizeof bits * 8;
    CHECK(sw_ofdm_demodulate(s, n, cfg, bits, &bit_len) == SW_OK);
    CHECK(bit_len == 2 * count);

    // Points carry the payload: QPSK Gray map 00:(+,+) 01:(-,+) 11:(-,-)
    // 10:(+,-), i.e. first bit = (Q < 0), second bit = (I < 0).
    int mismatches = 0;
    for (size_t k = 0; k < sizeof payload * 8 / 2; k++) {
        int b1 = iq[2 * k + 1] < 0.0f;
        int b2 = iq[2 * k] < 0.0f;
        if (b1 != bit_at(payload, 2 * k) || b2 != bit_at(payload, 2 * k + 1))
            mismatches++;
    }
    CHECK(mismatches == 0);

    double evm = evm_rms(iq, count, 1);
    printf("QPSK: %zu points, EVM %.4f%%\n", count, evm * 100.0);
    CHECK(evm < 0.2);

    // A smaller capacity truncates to the first points of the same frame.
    float iq_small[20];
    size_t small = 10;
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq_small, &small) == SW_OK);
    CHECK(small == 10);
    CHECK(memcmp(iq_small, iq, sizeof iq_small) == 0);

    free(iq);
    free(s);
}

static void test_bpsk_points_on_real_axis(void) {
    uint8_t payload[8] = {0xA5, 0x3C, 0xFF, 0x00, 0x12, 0x34, 0x56, 0x78};
    sw_config_t cfg = ofdm_config(0);
    size_t n = 0;
    float* s = modulate(payload, sizeof payload, cfg, &n);
    if (!s) return;

    float* iq = (float*)malloc(2 * MAX_POINTS * sizeof(float));
    size_t count = MAX_POINTS;
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq, &count) == SW_OK);
    CHECK(count >= sizeof payload * 8);

    int mismatches = 0;
    for (size_t k = 0; k < sizeof payload * 8; k++) {
        int bit = iq[2 * k] > 0.0f; // bpsk_map: 0 -> -1, 1 -> +1
        if (bit != bit_at(payload, k)) mismatches++;
    }
    CHECK(mismatches == 0);

    double evm = evm_rms(iq, count, 0);
    printf("BPSK: %zu points, EVM %.4f%%\n", count, evm * 100.0);
    CHECK(evm < 0.2);

    free(iq);
    free(s);
}

static void test_bad_params(void) {
    sw_config_t cfg = ofdm_config(1);
    float s[64] = {0};
    float iq[8];
    size_t count = 4;

    CHECK(sw_ofdm_equalized_symbols(NULL, 64, cfg, iq, &count) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, 64, cfg, NULL, &count) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, 64, cfg, iq, NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, 0, cfg, iq, &count) == SW_ERR_BAD_PARAM);
    count = 0;
    CHECK(sw_ofdm_equalized_symbols(s, 64, cfg, iq, &count) == SW_ERR_BAD_PARAM);

    // CSS configs have no OFDM constellation.
    sw_config_t css = cfg;
    css.modulation = 0;
    count = 4;
    CHECK(sw_ofdm_equalized_symbols(s, 64, css, iq, &count) == SW_ERR_BAD_PARAM);

    // Invalid OFDM config (non power-of-two FFT) is rejected by validation.
    sw_config_t bad = cfg;
    bad.num_subcarriers = 300;
    count = 4;
    CHECK(sw_ofdm_equalized_symbols(s, 64, bad, iq, &count) == SW_ERR_BAD_PARAM);

    // Too short for a preamble + one data symbol: an error, no points.
    count = 4;
    int rc = sw_ofdm_equalized_symbols(s, 64, cfg, iq, &count);
    CHECK(rc != SW_OK);
    CHECK(count == 0);
}

int main(void) {
    test_qpsk_points_match_payload();
    test_bpsk_points_on_real_axis();
    test_bad_params();
    if (failures) {
        fprintf(stderr, "%d constellation check(s) failed\n", failures);
        return 1;
    }
    printf("All constellation API tests passed.\n");
    return 0;
}
