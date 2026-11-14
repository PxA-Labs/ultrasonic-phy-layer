// Tests for sw_ofdm_equalized_symbols(): the equalized OFDM constellation
// points exposed for the Flutter constellation diagram (issue #71).
//
// Uses an explicit CHECK macro instead of assert() so the checks also run in
// Release builds (NDEBUG).

#include "soundwave_api.h"
#include "soundwave/ofdm.h"
#include <math.h>
#include <stdint.h>
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

// A noiseless TX -> RX loopback is exact up to float32 rounding (~1e-5 EVM).
// 1 % leaves room for FFT/libm differences across platforms while still
// catching any systematic impairment: a single sample of ISI from a late FFT
// window costs ~20 %, and the analytic-signal bug fixed with this bound
// (positive bins only half doubled) cost 28-45 %.
#define EVM_NOISELESS_MAX 0.01

// Data subcarriers per OFDM symbol for N = 256 in the default 18-20 kHz band:
// bins 106..115 (one guard bin inside each band edge), pilots on 106 and 114.
#define DATA_PER_SYMBOL 8

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

// The modulator whitens the data bits (ofdm_scramble), so the constellation
// points carry payload XOR PRBS15. Returns that on-air bit sequence.
static void on_air_bits(const uint8_t* payload, size_t nbytes, uint8_t* out) {
    memcpy(out, payload, nbytes);
    ofdm_scramble(out, nbytes * 8);
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
    // No trailing padding: a buffer that ends at the frame's last sample
    // yields every data symbol (and nothing after it).
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
    uint8_t payload[32], air[32];
    for (int i = 0; i < 32; i++) payload[i] = (uint8_t)(i * 37 + 11);
    on_air_bits(payload, sizeof payload, air);
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
        if (b1 != bit_at(air, 2 * k) || b2 != bit_at(air, 2 * k + 1))
            mismatches++;
    }
    CHECK(mismatches == 0);

    double evm = evm_rms(iq, count, 1);
    double mag = 0.0;
    for (size_t k = 0; k < count; k++) {
        double r = iq[2 * k], i = iq[2 * k + 1];
        mag += sqrt(r * r + i * i);
    }
    printf("QPSK: %zu points, EVM %.4f%%, mean |x| %.4f\n", count,
           evm * 100.0, count ? mag / (double)count : 0.0);
    for (size_t k0 = 0; k0 < count; k0 += 20) {
        size_t m = count - k0 < 20 ? count - k0 : 20;
        printf("  points %3zu..%3zu: EVM %6.2f%%\n", k0, k0 + m - 1,
               evm_rms(iq + 2 * k0, m, 1) * 100.0);
    }
    CHECK(evm < EVM_NOISELESS_MAX);
    CHECK(fabs(mag / (double)count - 1.0) < EVM_NOISELESS_MAX); // unit-energy QPSK

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
    uint8_t payload[8] = {0xA5, 0x3C, 0xFF, 0x00, 0x12, 0x34, 0x56, 0x78}, air[8];
    on_air_bits(payload, sizeof payload, air);
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
        if (bit != bit_at(air, k)) mismatches++;
    }
    CHECK(mismatches == 0);

    double evm = evm_rms(iq, count, 0);
    printf("BPSK: %zu points, EVM %.4f%%\n", count, evm * 100.0);
    for (size_t k0 = 0; k0 < count; k0 += 20) {
        size_t m = count - k0 < 20 ? count - k0 : 20;
        printf("  points %3zu..%3zu: EVM %6.2f%%\n", k0, k0 + m - 1,
               evm_rms(iq + 2 * k0, m, 0) * 100.0);
    }
    CHECK(evm < EVM_NOISELESS_MAX);

    free(iq);
    free(s);
}

// Deterministic uniform noise in [-1, 1) (platform-independent, unlike rand()).
static uint32_t lcg_state = 12345u;
static double lcg_uniform(void) {
    lcg_state = lcg_state * 1664525u + 1013904223u;
    return (double)(lcg_state >> 8) / 8388608.0 - 1.0;
}

typedef struct {
    double evm;      // RMS EVM over the frame's data symbols
    int errors;      // hard-decision errors against the transmitted bits
    size_t points;   // points evaluated
} loopback_t;

// TX -> RX loopback through sw_ofdm_equalized_symbols():
//   lead  samples of leading silence (detector must find the frame),
//   drop  first samples of the frame removed: the earliest possible FFT
//         window is then `drop` samples late (a known timing offset),
//   noise uniform noise amplitude added to every sample (0 = noiseless).
// EVM and decisions cover the frame's own data symbols only (a trailing
// silent symbol the detector may admit carries no data).
static loopback_t loopback(int ofdm_modulation, int cp, int equalizer,
                           size_t lead, size_t drop, double noise) {
    loopback_t res = {INFINITY, -1, 0};
    uint8_t payload[64], air[64];
    for (int i = 0; i < 64; i++) payload[i] = (uint8_t)(i * 151 + 29);
    on_air_bits(payload, sizeof payload, air);
    sw_config_t cfg = ofdm_config(ofdm_modulation);
    cfg.cp_length = cp;
    cfg.equalizer = equalizer;

    float* tx = (float*)malloc(MAX_SAMPLES * sizeof(float));
    float* rx = (float*)calloc(MAX_SAMPLES, sizeof(float));
    float* iq = (float*)malloc(2 * MAX_POINTS * sizeof(float));
    if (!tx || !rx || !iq) goto done;
    size_t tx_len = MAX_SAMPLES;
    if (sw_ofdm_modulate(payload, sizeof payload * 8, cfg, tx, &tx_len) != SW_OK) goto done;

    size_t sym = (size_t)(cfg.num_subcarriers + cp);
    size_t frame_syms = tx_len / sym - 2;
    size_t n = lead + (tx_len - drop); // ends at the frame's last sample
    if (n > MAX_SAMPLES) goto done;
    memcpy(rx + lead, tx + drop, (tx_len - drop) * sizeof(float));
    if (noise > 0.0) {
        for (size_t k = 0; k < n; k++) rx[k] += (float)(noise * lcg_uniform());
    }

    size_t count = MAX_POINTS;
    if (sw_ofdm_equalized_symbols(rx, n, cfg, iq, &count) != SW_OK) goto done;
    size_t want = frame_syms * DATA_PER_SYMBOL;
    if (count < want) goto done;

    int errors = 0;
    size_t nbits = sizeof payload * 8;
    for (size_t k = 0; k < want; k++) {
        float re = iq[2 * k], im = iq[2 * k + 1];
        if (ofdm_modulation == 0) {
            int bit = k < nbits ? bit_at(air, k) : 0; // bpsk_map: 0 -> -1
            errors += (re > 0.0f) != bit;
        } else {
            int b1 = 2 * k < nbits ? bit_at(air, 2 * k) : 0;
            int b2 = 2 * k + 1 < nbits ? bit_at(air, 2 * k + 1) : 0;
            errors += (im < 0.0f) != b1;
            errors += (re < 0.0f) != b2;
        }
    }
    res.evm = evm_rms(iq, want, ofdm_modulation);
    res.errors = errors;
    res.points = want;
done:
    free(tx);
    free(rx);
    free(iq);
    return res;
}

static void check_case(const char* what, int mod, int cp, int eq, size_t lead,
                       size_t drop, double noise, double evm_lo, double evm_hi) {
    loopback_t r = loopback(mod, cp, eq, lead, drop, noise);
    printf("%-22s %s cp=%2d %s lead=%3zu drop=%2zu noise=%.2f: %zu points, "
           "EVM %.4f%%, %d bit errors\n",
           what, mod ? "QPSK" : "BPSK", cp, eq ? "MMSE" : "ZF  ", lead, drop,
           noise, r.points, r.evm * 100.0, r.errors);
    CHECK(r.points > 0);
    CHECK(r.errors == 0);
    CHECK(r.evm >= evm_lo);
    CHECK(r.evm < evm_hi);
}

// Noiseless loopback: BPSK/QPSK x CP 32/64 x ZF/MMSE, with the frame at the
// start of the buffer and after leading silence.
static void test_noiseless_loopback_evm(void) {
    const int cps[2] = {32, 64};
    const size_t leads[3] = {0, 5, 300};
    for (int mod = 0; mod <= 1; mod++)
        for (int c = 0; c < 2; c++)
            for (int eq = 0; eq <= 1; eq++)
                for (int l = 0; l < 3; l++)
                    check_case("noiseless", mod, cps[c], eq, leads[l], 0, 0.0,
                               0.0, EVM_NOISELESS_MAX);
}

// Timing offsets inside the CP. The receiver samples every symbol
// OFDM_TIMING_BACKOFF(cp) = cp/4 samples early (MATHEMATICAL_MODEL.md 4.0),
// so a window up to cp/4 samples late is still ISI-free. With no leading
// silence, dropping the first `drop` samples of the frame forces the detected
// start, and with it every FFT window, at least `drop` samples late; the
// channel estimate's phase ramp then still matches the data symbols. (After
// leading silence the detector would just find the frame's virtual start.)
static void test_timing_offset_within_cp(void) {
    const int cps[2] = {32, 64};
    for (int mod = 0; mod <= 1; mod++) {
        for (int c = 0; c < 2; c++) {
            size_t b = (size_t)cps[c] / 4;
            size_t drops[3];
            drops[0] = 1;
            drops[1] = b / 2;
            drops[2] = b - 1;
            for (int d = 0; d < 3; d++)
                check_case("late timing", mod, cps[c], 0, 0, drops[d], 0.0,
                           0.0, EVM_NOISELESS_MAX);
        }
    }
}

// Noise must show up in the EVM at the predicted level. Uniform noise of
// amplitude A has variance A^2/3 per sample, and the unitary DFT keeps that
// per subcarrier. The ZF error is W - X (W1 + W2) / 2 (data noise plus the
// two-copy channel-estimate noise), so EVM = sqrt(1.5 A^2 / 3) = 1.41 % for
// A = 0.02. The per-symbol common-phase correction from the two pilots adds
// a phase error of variance (A^2/3) / 4, i.e. sqrt(1.5 + 0.25) A / sqrt(3) =
// 1.53 %. The window allows for the finite sample of points.
static void test_noise_evm_matches_theory(void) {
    for (int eq = 0; eq <= 1; eq++) {
        check_case("noise A=0.02", 1, 32, eq, 0, 0, 0.02, 0.010, 0.020);
        check_case("noise A=0.02", 1, 64, eq, 200, 0, 0.02, 0.010, 0.020);
    }
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

static void test_layout_matches_constant(void) {
    ofdm_layout_t lay;
    CHECK(ofdm_layout_compute(256, 44100.0f, 19000.0f, 2000.0f, &lay) == SW_OK);
    CHECK(lay.first_bin == 106 && lay.last_bin == 115);
    CHECK(lay.num_data == DATA_PER_SYMBOL);
}

int main(void) {
    test_layout_matches_constant();
    test_qpsk_points_match_payload();
    test_bpsk_points_on_real_axis();
    test_noiseless_loopback_evm();
    test_timing_offset_within_cp();
    test_noise_evm_matches_theory();
    test_bad_params();
    if (failures) {
        fprintf(stderr, "%d constellation check(s) failed\n", failures);
        return 1;
    }
    printf("All constellation API tests passed.\n");
    return 0;
}
