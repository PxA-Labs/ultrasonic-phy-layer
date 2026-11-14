// Transmit level contract: every modulator frame satisfies
//
//     max |sample| <= cfg.amplitude   (amplitude in (0, 1]; 0 selects 0.8)
//
// so the app can play it and the CLI can write 16-bit PCM without clipping.
// Clipping would splatter energy into the audible band (defeating the
// ultrasonic confinement) and distort the constellation.
//
//   * OFDM: deterministic per-frame peak normalization -- one gain per frame,
//     peak == amplitude. Checked over N 128..4096, three CP lengths,
//     BPSK/QPSK, several bands and sample rates, random and worst-case
//     payloads (all-zero, all-0xFF, alternating). The raw (pre-normalization)
//     peak, i.e. what the modulator used to output, is reported per config.
//   * The scaling is a pure gain: frames at two amplitudes are proportional,
//     and both decode (the receiver is scale-invariant).
//   * CSS: constant-envelope chirps, peak == amplitude, for SF 6..10 and
//     several bandwidths.
//
// Uses CHECK instead of assert() so it also runs in Release (NDEBUG) builds.

#include "soundwave_api.h"
#include "soundwave/ofdm.h"
#include "soundwave/css.h"
#include "ofdm_gain_util.h"
#include <float.h>
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

#define PAYLOAD_BYTES 64
#define NUM_PAYLOADS 4
#define MAX_SAMPLES (1u << 20)

static const char* payload_names[NUM_PAYLOADS] = {"random", "zeros", "0xFF", "0xAA55"};

static void make_payloads(uint8_t p[NUM_PAYLOADS][PAYLOAD_BYTES], uint32_t seed) {
    for (int i = 0; i < PAYLOAD_BYTES; i++) {
        seed = seed * 1664525u + 1013904223u;
        p[0][i] = (uint8_t)(seed >> 24);
        p[1][i] = 0x00;
        p[2][i] = 0xFF;
        p[3][i] = (i & 1) ? 0x55 : 0xAA;
    }
}

static float peak_of(const float* s, size_t n) {
    float pk = 0.0f;
    for (size_t i = 0; i < n; i++) {
        float a = fabsf(s[i]);
        if (a > pk) pk = a;
    }
    return pk;
}

static double rms_of(const float* s, size_t n) {
    double e = 0.0;
    for (size_t i = 0; i < n; i++) e += (double)s[i] * (double)s[i];
    return n ? sqrt(e / (double)n) : 0.0;
}

// Upper bound with float slack (the implementation clamps, so it is exact).
static int within(float peak, float amp) {
    return peak <= amp * (1.0f + FLT_EPSILON);
}

static sw_config_t base_cfg(int modulation) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100;
    c.modulation = modulation;
    c.sf = 8;
    c.num_subcarriers = 256;
    c.cp_length = 64;
    c.num_pilots = 8;
    c.threshold = 3.0f;
    c.carrier_freq = 19000.0f;
    c.bandwidth = 2000.0f;
    c.amplitude = 0.8f;
    c.ofdm_modulation = 1;
    return c;
}

/* ------------------------------------------------------------------------ */

static void test_ofdm_matrix(float* tx) {
    struct { int fs; float fc, bw; } bands[] = {
        {44100, 19000.0f, 2000.0f}, // app default 18-20 kHz
        {44100, 19500.0f, 3000.0f}, // 18-21 kHz
        {48000, 20000.0f, 4000.0f}, // 18-22 kHz at 48 kHz
        {44100, 14000.0f, 8000.0f}, // wide band: highest crest factor
    };
    const int Ns[] = {128, 256, 512, 1024, 2048, 4096};
    const float amps[] = {0.0f, 0.25f, 0.8f, 1.0f}; // 0 = default 0.8
    uint8_t p[NUM_PAYLOADS][PAYLOAD_BYTES];
    make_payloads(p, 0x5eed1234u);

    size_t frames = 0;
    double worst_raw = 0.0;
    printf("%-6s %-5s %-4s %-17s %10s %10s %9s\n", "N", "cp", "mod", "band",
           "raw peak", "max crest", "frames");
    for (size_t b = 0; b < sizeof bands / sizeof *bands; b++) {
        for (size_t ni = 0; ni < sizeof Ns / sizeof *Ns; ni++) {
            int N = Ns[ni];
            const int cps[3] = {N / 16, 0 /* default N/8 */, N / 4};
            for (int ci = 0; ci < 3; ci++) {
                for (int mod = 0; mod <= 1; mod++) {
                    sw_config_t c = base_cfg(1);
                    c.sample_rate = bands[b].fs;
                    c.carrier_freq = bands[b].fc;
                    c.bandwidth = bands[b].bw;
                    c.num_subcarriers = N;
                    c.cp_length = cps[ci];
                    c.ofdm_modulation = mod;
                    if (sw_config_validate(c) != SW_OK) continue; // band too narrow for N
                    double raw_max = 0.0, crest_max = 0.0;
                    int n_ok = 0;
                    for (int pi = 0; pi < NUM_PAYLOADS; pi++) {
                        float amp_cfg = amps[(pi + ci + mod) % 4];
                        float amp = amp_cfg > 0.0f ? amp_cfg : OFDM_DEFAULT_AMPLITUDE;
                        c.amplitude = amp_cfg;
                        size_t n = MAX_SAMPLES;
                        int rc = sw_ofdm_modulate(p[pi], PAYLOAD_BYTES * 8, c, tx, &n);
                        CHECK(rc == SW_OK);
                        if (rc != SW_OK) continue;
                        float pk = peak_of(tx, n);
                        int ok = within(pk, amp) && pk >= amp * (1.0f - 1e-6f);
                        if (!ok)
                            fprintf(stderr, "OFDM N=%d cp=%d mod=%d fs=%d %.0f/%.0f %s amp=%.2f: peak %.7f\n",
                                    N, cps[ci], mod, bands[b].fs, bands[b].fc, bands[b].bw,
                                    payload_names[pi], amp, pk);
                        CHECK(ok);
                        double g = ofdm_frame_gain(tx, n, c);
                        CHECK(g > 0.0);
                        if (g > 0.0 && amp / g > raw_max) raw_max = amp / g;
                        double crest = pk / rms_of(tx, n);
                        if (crest > crest_max) crest_max = crest;
                        frames++;
                        n_ok++;
                    }
                    if (raw_max > worst_raw) worst_raw = raw_max;
                    if (n_ok && ci == 1) {
                        char band[32];
                        snprintf(band, sizeof band, "%d:%.0f+-%.0f", bands[b].fs,
                                 bands[b].fc, bands[b].bw / 2);
                        printf("%-6d %-5d %-4s %-17s %10.3f %8.2fdB %9d\n", N, N / 8,
                               mod ? "QPSK" : "BPSK", band, raw_max,
                               20.0 * log10(crest_max), n_ok);
                    }
                }
            }
        }
    }
    CHECK(frames >= 300); // the matrix really ran
    printf("PASS: %zu OFDM frames, max|x| <= amplitude (worst raw peak before "
           "normalization %.3f)\n", frames, worst_raw);
}

// Scaling is a single gain per frame: output at amplitude a is a/b times the
// output at amplitude b, and both decode to the payload.
static void test_ofdm_scale_invariance(float* tx_a, float* tx_b) {
    const int Ns[2] = {256, 2048};
    uint8_t p[NUM_PAYLOADS][PAYLOAD_BYTES];
    make_payloads(p, 0xabcdef01u);
    for (int i = 0; i < 2; i++) {
        sw_config_t c = base_cfg(1);
        c.num_subcarriers = Ns[i];
        c.cp_length = Ns[i] / 4;
        c.amplitude = 0.25f;
        size_t na = MAX_SAMPLES, nb = MAX_SAMPLES;
        CHECK(sw_ofdm_modulate(p[0], PAYLOAD_BYTES * 8, c, tx_a, &na) == SW_OK);
        c.amplitude = 1.0f;
        CHECK(sw_ofdm_modulate(p[0], PAYLOAD_BYTES * 8, c, tx_b, &nb) == SW_OK);
        CHECK(na == nb);
        double max_err = 0.0;
        for (size_t k = 0; k < na && k < nb; k++) {
            double e = fabs((double)tx_a[k] - 0.25 * (double)tx_b[k]);
            if (e > max_err) max_err = e;
        }
        CHECK(max_err < 1e-6);

        const float amps[2] = {0.25f, 1.0f};
        float* bufs[2] = {tx_a, tx_b};
        for (int a = 0; a < 2; a++) {
            c.amplitude = amps[a];
            uint8_t out[512];
            size_t bits = sizeof out * 8;
            int rc = sw_ofdm_demodulate(bufs[a], na, c, out, &bits);
            int ok = rc == SW_OK && bits >= PAYLOAD_BYTES * 8 &&
                     memcmp(out, p[0], PAYLOAD_BYTES) == 0;
            if (!ok) fprintf(stderr, "N=%d amp=%.2f: decode rc %d\n", Ns[i], amps[a], rc);
            CHECK(ok);
        }
    }
    printf("PASS: OFDM level scaling is a pure gain; frames decode at amplitude 0.25 and 1.0\n");
}

// Internal entry points: ofdm_modulate_frame with out-of-range amplitudes,
// and ofdm_peak_normalize edge cases.
static void test_ofdm_internal(float* tx) {
    ofdm_config_t oc;
    memset(&oc, 0, sizeof oc);
    oc.num_subcarriers = 256;
    oc.cp_length = 32;
    oc.modulation = 1;
    ofdm_init(&oc);
    CHECK(oc.amplitude == OFDM_DEFAULT_AMPLITUDE);
    uint8_t p[NUM_PAYLOADS][PAYLOAD_BYTES];
    make_payloads(p, 7u);
    const float amps[] = {0.0f, -1.0f, 1.5f, NAN, 0.5f};
    for (size_t i = 0; i < sizeof amps / sizeof *amps; i++) {
        oc.amplitude = amps[i];
        float want = (amps[i] > 0.0f && amps[i] <= 1.0f) ? amps[i] : OFDM_DEFAULT_AMPLITUDE;
        size_t n = MAX_SAMPLES;
        CHECK(ofdm_modulate_frame(&oc, p[0], PAYLOAD_BYTES * 8, tx, &n) == SW_OK);
        float pk = peak_of(tx, n);
        CHECK(within(pk, want) && pk >= want * (1.0f - 1e-6f));
    }

    float x[4] = {0.5f, -2.0f, 1.0f, 0.0f};
    CHECK(fabsf(ofdm_peak_normalize(x, 4, 0.8f) - 0.4f) < 1e-6f);
    CHECK(x[1] == -0.8f && fabsf(x[0] - 0.2f) < 1e-7f && x[3] == 0.0f);
    float z[3] = {0.0f, 0.0f, 0.0f};
    CHECK(ofdm_peak_normalize(z, 3, 0.8f) == 0.0f); // silence stays silence
    CHECK(z[0] == 0.0f && z[1] == 0.0f && z[2] == 0.0f);
    CHECK(ofdm_peak_normalize(NULL, 3, 0.8f) == 0.0f);
    CHECK(ofdm_peak_normalize(x, 0, 0.8f) == 0.0f);
    CHECK(ofdm_peak_normalize(x, 4, 0.0f) == 0.0f);
    // Values whose scaled peak rounds above the target are clamped to it.
    for (int k = 1; k < 2000; k++) {
        float y[2] = {(float)k * 1.000123f, -(float)k * 0.37f};
        float amp = 0.1f + 0.0004f * (float)k;
        ofdm_peak_normalize(y, 2, amp);
        CHECK(fabsf(y[0]) <= amp && fabsf(y[1]) <= amp);
    }
    printf("PASS: ofdm_modulate_frame / ofdm_peak_normalize level handling\n");
}

/* ------------------------------------------------------------------------ */

static void test_css_matrix(float* tx) {
    const float bws[3] = {1000.0f, 2000.0f, 4000.0f};
    const float amps[4] = {0.0f, 0.3f, 0.8f, 1.0f};
    uint8_t p[NUM_PAYLOADS][PAYLOAD_BYTES];
    make_payloads(p, 0x0badf00du);
    size_t frames = 0;
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
        for (int b = 0; b < 3; b++) {
            sw_config_t c = base_cfg(0);
            c.sf = sf;
            c.bandwidth = bws[b];
            if (sw_config_validate(c) != SW_OK) continue; // symbol longer than 1 s
            for (int pi = 0; pi < NUM_PAYLOADS; pi++) {
                float amp_cfg = amps[(pi + sf + b) % 4];
                float amp = amp_cfg > 0.0f ? amp_cfg : 0.8f;
                c.amplitude = amp_cfg;
                // 16 bytes keep SF10 frames short; the envelope is constant
                // anyway, the payloads just pick different chirp shifts.
                size_t n = MAX_SAMPLES;
                int rc = sw_css_modulate(p[pi], 16 * 8, c, tx, &n);
                CHECK(rc == SW_OK);
                if (rc != SW_OK) continue;
                float pk = peak_of(tx, n);
                int ok = within(pk, amp) && pk >= 0.99f * amp;
                if (!ok)
                    fprintf(stderr, "CSS SF%d B=%.0f %s amp=%.2f: peak %.7f\n", sf, bws[b],
                            payload_names[pi], amp, pk);
                CHECK(ok);
                frames++;
            }
        }
    }
    CHECK(frames >= 40);

    // Amplitudes above full scale are rejected, not clipped.
    sw_config_t c = base_cfg(0);
    c.amplitude = 1.5f;
    css_geometry_t g;
    CHECK(css_geometry(&c, &g) != 0);
    size_t n = MAX_SAMPLES;
    CHECK(sw_css_modulate(p[0], 64, c, tx, &n) == SW_ERR_BAD_PARAM);
    sw_signal s = css_modulate(p[0], 64, c);
    CHECK(s.data == NULL);
    printf("PASS: %zu CSS frames, max|x| <= amplitude\n", frames);
}

int main(void) {
    float* a = (float*)malloc(MAX_SAMPLES * sizeof(float));
    float* b = (float*)malloc(MAX_SAMPLES * sizeof(float));
    if (!a || !b) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }
    test_ofdm_matrix(a);
    test_ofdm_scale_invariance(a, b);
    test_ofdm_internal(a);
    test_css_matrix(a);
    free(a);
    free(b);
    if (failures) {
        fprintf(stderr, "%d transmit level check(s) failed\n", failures);
        return 1;
    }
    printf("All transmit level tests passed.\n");
    return 0;
}
