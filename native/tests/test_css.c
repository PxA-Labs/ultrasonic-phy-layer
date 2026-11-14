// Unit tests for CSS modulation, synchronisation and demodulation.
// References: MATHEMATICAL_MODEL.md sections 2.1-2.3.

#include "soundwave/css.h"
#include "soundwave/sync.h"
#include "soundwave/common.h"
#include "soundwave_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
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

// Deterministic, platform-independent RNG (xorshift64*) + Box-Muller.
static uint64_t rng_state = 0x9E3779B97F4A7C15ull;
static uint32_t rng_u32(void) {
    rng_state ^= rng_state >> 12;
    rng_state ^= rng_state << 25;
    rng_state ^= rng_state >> 27;
    return (uint32_t)((rng_state * 0x2545F4914F6CDD1Dull) >> 32);
}
static double rng_uniform(void) { return ((double)rng_u32() + 1.0) / 4294967297.0; }
static double rng_gauss(void) {
    double u1 = rng_uniform(), u2 = rng_uniform();
    return sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2);
}

static double mean_power(const float* x, size_t n) {
    double p = 0.0;
    for (size_t i = 0; i < n; i++) p += (double)x[i] * x[i];
    return n ? p / (double)n : 0.0;
}

// Adds white Gaussian noise of power `power` to x.
static void add_noise(float* x, size_t n, double power) {
    double sd = sqrt(power);
    for (size_t i = 0; i < n; i++) x[i] += (float)(sd * rng_gauss());
}

static int bit_at(const uint8_t* b, size_t i) { return (b[i / 8] >> (7 - i % 8)) & 1; }

static size_t bit_errors(const uint8_t* a, const uint8_t* b, size_t nbits) {
    size_t e = 0;
    for (size_t i = 0; i < nbits; i++) e += bit_at(a, i) != bit_at(b, i);
    return e;
}

static sw_config_t css_cfg(int sf, float bw) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100;
    c.modulation = 0;
    c.sf = sf;
    c.carrier_freq = 19000.0f;
    c.bandwidth = bw;
    c.amplitude = 0.8f;
    c.threshold = 3.0f;
    return c;
}

// Builds [lead][frame][tail]; lead_kind 0 = silence, 1 = noise, 2 = CSS data
// symbols (another frame's payload without its preamble). Returns the buffer;
// *n is its length, the frame starts at sample `lead`.
static float* build_rx(const sw_config_t* cfg, const uint8_t* payload, size_t nbits,
                       size_t lead, int lead_kind, size_t tail, size_t* n) {
    sw_signal f = css_modulate(payload, nbits, *cfg);
    CHECK(f.data != NULL);
    *n = lead + f.length + tail;
    float* x = (float*)calloc(*n, sizeof(float));
    CHECK(x != NULL);
    memcpy(x + lead, f.data, f.length * sizeof(float));
    double p = mean_power(f.data, f.length);
    if (lead_kind == 1) {
        double sd = sqrt(p); // 0 dB full-band noise burst before the frame
        for (size_t i = 0; i < lead; i++) x[i] = (float)(sd * rng_gauss());
    } else if (lead_kind == 2 && lead > 0) {
        css_geometry_t g;
        CHECK(css_geometry(cfg, &g) == 0);
        size_t junk_bits = (lead / (size_t)g.N + 1) * (size_t)g.sf;
        uint8_t* junk = (uint8_t*)calloc((junk_bits + 7) / 8, 1);
        CHECK(junk != NULL);
        // Zero runs (base up-chirps, i.e. the up part of the preamble) and
        // random bytes.
        for (size_t i = (junk_bits + 7) / 16; i < (junk_bits + 7) / 8; i++)
            junk[i] = (uint8_t)rng_u32();
        sw_signal j = css_modulate(junk, junk_bits, *cfg);
        CHECK(j.data != NULL);
        size_t pre = CSS_PREAMBLE_SYMBOLS * (size_t)g.N;
        size_t avail = j.length - pre;
        size_t take = avail < lead ? avail : lead;
        memcpy(x + lead - take, j.data + pre, take * sizeof(float));
        free(j.data);
        free(junk);
    }
    free(f.data);
    return x;
}

static void test_legacy_raw_helpers(void) {
    css_config_t raw_cfg = {
        .sf = 8, .bandwidth = 2000.0f, .sample_rate = 44100.0f, .f0 = 18000.0f
    };
    css_init(&raw_cfg);
    int N = raw_cfg.chirp_len, SF = raw_cfg.sf;
    float* up = (float*)malloc(N * sizeof(float));
    float* down = (float*)malloc(N * sizeof(float));
    float* sym = (float*)malloc(N * sizeof(float));
    CHECK(up && down && sym);
    css_generate_upchirp_raw(&raw_cfg, up);
    css_generate_downchirp_raw(&raw_cfg, down);
    for (int n = 0; n < N; n++) CHECK(fabsf(up[n] - down[n]) <= 1e-6f);
    const int vals[] = {0, 42, 128};
    for (int i = 0; i < 3; i++) {
        css_modulate_symbol_raw(&raw_cfg, vals[i], sym);
        CHECK(css_extract_symbol(sym, N, down, 8192, SF) == vals[i]);
    }
    free(up); free(down); free(sym);
    printf("PASS: legacy raw chirp helpers\n");
}

// Geometry: integer samples per chip, B_eff = fs / D, N = 2^SF * D, SF bits
// per symbol, rejected configs.
static void test_geometry(void) {
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
        sw_config_t c = css_cfg(sf, 4000.0f);
        css_geometry_t g;
        CHECK(css_geometry(&c, &g) == 0);
        CHECK(g.D == 11 && g.M == (1 << sf) && g.N == g.M * 11);
        CHECK(fabs(g.B - 44100.0 / 11.0) < 1e-9);
        CHECK(css_num_symbols(&g, 100) == (size_t)((100 + sf - 1) / sf));
        CHECK(css_frame_samples(&g, 100) ==
              (size_t)(CSS_PREAMBLE_SYMBOLS + (100 + sf - 1) / sf) * (size_t)g.N);
        printf("  SF%-2d B=4 kHz: D=%d, N=%d samples (%.1f ms), %.1f bit/s raw\n", sf, g.D,
               g.N, 1000.0 * g.N / g.fs, sf * g.B / g.M);
        c = css_cfg(sf, 2000.0f);
        CHECK(css_geometry(&c, &g) == 0 && g.D == 22 && g.N == (1 << sf) * 22);
    }
    sw_config_t c = css_cfg(5, 2000.0f);
    css_geometry_t g;
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(11, 2000.0f);
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(10, 1000.0f); // 1.02 s symbol
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.carrier_freq = 21500.0f; // band edge 22.5 kHz > fs / 2
    CHECK(css_geometry(&c, &g) != 0);
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = css_cfg(8, 2000.0f);
    c.symbol_duration = 0.02f; // ignored by CSS
    CHECK(css_geometry(&c, &g) == 0 && g.N == 256 * 22);
    printf("PASS: CSS geometry (D, B_eff, N, SF range, band limits)\n");
}

// Exhaustive symbol coverage: every symbol value of SF6 and SF8 round-trips.
static void test_all_symbols(void) {
    const int sfs[] = {6, 8};
    for (int t = 0; t < 2; t++) {
        int sf = sfs[t];
        int M = 1 << sf;
        size_t nbits = (size_t)M * sf;
        uint8_t* bits = (uint8_t*)calloc((nbits + 7) / 8, 1);
        CHECK(bits != NULL);
        for (int s = 0; s < M; s++) // the Gray code of s, so every symbol is sent
            for (int b = 0; b < sf; b++) {
                size_t i = (size_t)s * sf + b;
                if (((s ^ (s >> 1)) >> (sf - 1 - b)) & 1) bits[i / 8] |= (uint8_t)(0x80 >> (i % 8));
            }
        sw_config_t c = css_cfg(sf, 4000.0f);
        sw_signal f = css_modulate(bits, nbits, c);
        CHECK(f.data != NULL);
        size_t ob = 0;
        uint8_t* out = css_demodulate(f.data, f.length, c, &ob);
        CHECK(out != NULL && ob * 8 >= nbits);
        CHECK(bit_errors(bits, out, nbits) == 0);
        free(out); free(f.data); free(bits);
    }
    printf("PASS: all 64 SF6 and 256 SF8 symbol values round-trip\n");
}

// Gray mapping: adjacent symbols (the likely error) differ in exactly 1 bit.
static void test_gray_adjacent(void) {
    sw_config_t c = css_cfg(7, 4000.0f);
    css_geometry_t g;
    CHECK(css_geometry(&c, &g) == 0);
    // Symbols k and k+1 come from data values Gray(k) and Gray(k+1).
    for (int k = 0; k < g.M; k++) {
        int a = k ^ (k >> 1), b = ((k + 1) % g.M) ^ (((k + 1) % g.M) >> 1);
        int d = a ^ b, ones = 0;
        while (d) { ones += d & 1; d >>= 1; }
        CHECK(ones == 1);
    }
    printf("PASS: Gray mapping, adjacent bins differ in one bit\n");
}

// Problem 2: sync must find the frame anywhere in the buffer.
static void test_sync_offsets(void) {
    const double leads_s[] = {0.0, 0.037, 1.0};
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf += 2) {
        sw_config_t c = css_cfg(sf, 2000.0f);
        css_geometry_t g;
        CHECK(css_geometry(&c, &g) == 0);
        uint8_t payload[24];
        for (int i = 0; i < 24; i++) payload[i] = (uint8_t)rng_u32();
        for (int kind = 0; kind < 3; kind++) {
            for (int l = 0; l < 3; l++) {
                if (kind == 2 && l == 0) continue;
                size_t lead = (size_t)(leads_s[l] * 44100.0 + 0.5);
                size_t n = 0;
                float* x = build_rx(&c, payload, 24 * 8, lead, kind, (size_t)g.N / 3, &n);
                css_sync_result_t r;
                CHECK(css_detect_frame(x, n, &g, 3.0f, &r) == 1);
                CHECK(fabs(r.start - (double)lead) < 1.0);
                size_t det = 0;
                float snr = 0.0f;
                CHECK(sw_detect_frame(x, n, c, &det, &snr) == SW_OK && det == lead);
                size_t ob = 0;
                uint8_t* out = css_demodulate(x, n, c, &ob);
                CHECK(out != NULL && ob >= 24);
                CHECK(memcmp(out, payload, 24) == 0);
                printf("  SF%-2d %-7s lead %.3f s: start %.2f (true %zu), SNR %.1f dB\n", sf,
                       kind == 0 ? "silence" : kind == 1 ? "noise" : "CSS data", leads_s[l],
                       r.start, lead, r.snr_db);
                free(out);
                free(x);
            }
        }
    }
    printf("PASS: frame found after 0/37 ms/1 s of silence, noise and CSS data\n");
}

// Payloads that look like (parts of) the preamble must not move the lock.
static void test_preamble_like_payloads(void) {
    // 0x00 0xC0: the old up/down bit chirps formed 8 up + 2 down -> the old
    // preamble. All-zero bytes: runs of base up-chirps (the new preamble's
    // up part).
    uint8_t p_old[32], p_zero[32];
    for (int i = 0; i < 32; i++) {
        p_old[i] = (i % 2) ? 0xC0 : 0x00;
        p_zero[i] = 0x00;
    }
    const uint8_t* ps[2] = {p_old, p_zero};
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
        sw_config_t c = css_cfg(sf, 4000.0f);
        css_geometry_t g;
        CHECK(css_geometry(&c, &g) == 0);
        for (int t = 0; t < 2; t++) {
            size_t lead = 1234, n = 0;
            float* x = build_rx(&c, ps[t], 32 * 8, lead, 0, (size_t)g.N, &n);
            css_sync_result_t r;
            CHECK(css_detect_frame(x, n, &g, 3.0f, &r) == 1);
            CHECK(fabs(r.start - (double)lead) < 1.0);
            size_t ob = 0;
            uint8_t* out = css_demodulate(x, n, c, &ob);
            CHECK(out != NULL && ob >= 32 && memcmp(out, ps[t], 32) == 0);
            free(out);
            // The payload alone (preamble cut off) must not be detected.
            size_t pre = CSS_PREAMBLE_SYMBOLS * (size_t)g.N;
            CHECK(css_detect_frame(x + lead + pre, n - lead - pre, &g, 3.0f, &r) == 0);
            free(x);
        }
    }
    printf("PASS: preamble-like payloads neither shift nor fake the lock\n");
}

// Noise only (and digital silence) must not trigger detection.
static void test_no_false_alarm(void) {
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
        sw_config_t c = css_cfg(sf, 2000.0f);
        css_geometry_t g;
        CHECK(css_geometry(&c, &g) == 0);
        size_t n = 14 * (size_t)g.N;
        float* x = (float*)calloc(n, sizeof(float));
        CHECK(x != NULL);
        css_sync_result_t r;
        CHECK(css_detect_frame(x, n, &g, 3.0f, &r) == 0); // silence
        add_noise(x, n, 0.1);
        CHECK(css_detect_frame(x, n, &g, 3.0f, &r) == 0);
        size_t ob = 0;
        CHECK(css_demodulate(x, n, c, &ob) == NULL && ob == 0);
        free(x);
    }
    printf("PASS: no detection in silence or noise\n");
}

// BER per SF at modest AWGN. SNR is full-band (noise over 0..fs/2), as in
// soundwave-cli simulate; in-band SNR is ~10 log10(fs / 2B) = 10.4 dB higher
// at B = 2 kHz.
static void test_ber_per_sf(void) {
    const double snr_db = -7.0;
    for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
        sw_config_t c = css_cfg(sf, 2000.0f);
        css_geometry_t g;
        CHECK(css_geometry(&c, &g) == 0);
        size_t errs = 0, total = 0;
        for (int f = 0; f < 2; f++) {
            uint8_t payload[32];
            for (int i = 0; i < 32; i++) payload[i] = (uint8_t)rng_u32();
            size_t lead = 777 + 1000 * (size_t)f, n = 0;
            float* x = build_rx(&c, payload, 256, lead, 0, (size_t)g.N / 2, &n);
            double p = mean_power(x + lead, css_frame_samples(&g, 256));
            add_noise(x, n, p / pow(10.0, snr_db / 10.0));
            size_t ob = 0;
            uint8_t* out = css_demodulate(x, n, c, &ob);
            CHECK(out != NULL && ob >= 32);
            errs += bit_errors(payload, out, 256);
            total += 256;
            free(out);
            free(x);
        }
        double ber = (double)errs / (double)total;
        printf("  SF%-2d @ %.0f dB full-band SNR: %zu/%zu bit errors (BER %.4f)\n", sf, snr_db,
               errs, total, ber);
        CHECK(ber <= 0.005);
    }
    printf("PASS: BER <= 0.5%% for every SF at -7 dB full-band SNR\n");
}

// A carrier/Doppler offset of up to ~1 bin is estimated and removed.
static void test_frequency_offset(void) {
    sw_config_t c = css_cfg(8, 4000.0f);
    css_geometry_t g;
    CHECK(css_geometry(&c, &g) == 0);
    double bin = g.B / g.M;
    uint8_t payload[16];
    for (int i = 0; i < 16; i++) payload[i] = (uint8_t)rng_u32();
    const double offs[] = {-0.8, 0.4, 1.0};
    for (int t = 0; t < 3; t++) {
        // Receiver tuned off by df: equivalent to a carrier shifted by +df.
        sw_config_t tx = c;
        tx.carrier_freq = (float)(c.carrier_freq + offs[t] * bin);
        sw_signal f = css_modulate(payload, 128, tx);
        CHECK(f.data != NULL);
        size_t lead = 500, n = lead + f.length + (size_t)g.N;
        float* x = (float*)calloc(n, sizeof(float));
        CHECK(x != NULL);
        memcpy(x + lead, f.data, f.length * sizeof(float));
        css_sync_result_t r;
        CHECK(css_detect_frame(x, n, &g, 3.0f, &r) == 1);
        CHECK(fabs(r.cfo_hz - offs[t] * bin) < 0.25 * bin);
        CHECK(fabs(r.start - (double)lead) < (double)g.D);
        size_t ob = 0;
        uint8_t* out = css_demodulate(x, n, c, &ob);
        CHECK(out != NULL && memcmp(out, payload, 16) == 0);
        printf("  offset %+.1f bin (%+.2f Hz): estimated %+.2f Hz\n", offs[t], offs[t] * bin,
               r.cfo_hz);
        free(out); free(x); free(f.data);
    }
    printf("PASS: frequency offset estimated from up/down chirps and removed\n");
}

// Argument checks, hostile configs and inputs: rejected or handled, never UB.
static void test_edge_cases(void) {
    css_geometry_t g;
    sw_config_t c = css_cfg(8, 2000.0f);
    CHECK(css_geometry(NULL, &g) != 0 && css_geometry(&c, NULL) != 0);
    c.carrier_freq = NAN;
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.bandwidth = INFINITY;
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.amplitude = NAN;
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.sample_rate = 500; // below 1 kHz
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.bandwidth = 1e-30f; // absurd samples per chip
    CHECK(css_geometry(&c, &g) != 0);
    c = css_cfg(8, 2000.0f);
    c.carrier_freq = 500.0f; // band would start below 0 Hz
    CHECK(css_geometry(&c, &g) != 0);
    sw_config_t z;
    memset(&z, 0, sizeof z); // every default
    CHECK(css_geometry(&z, &g) == 0 && g.sf == 8 && g.D == 22 && g.fc == 19000.0);
    CHECK(fabs(g.amplitude - 0.8) < 1e-9);

    CHECK(css_frame_samples(&g, SIZE_MAX) == 0); // would overflow
    uint8_t one = 0xA5;
    size_t cap = 0;
    float dummy = 0.0f;
    CHECK(sw_css_modulate(&one, SIZE_MAX, z, &dummy, &cap) == SW_ERR_BAD_PARAM);
    sw_signal empty = css_modulate(NULL, 8, z);
    CHECK(empty.data == NULL && empty.length == 0);
    empty = css_modulate(&one, 0, z);
    CHECK(empty.data == NULL);

    // A clean frame for the receiver-side cases.
    sw_signal f = css_modulate(&one, 8, z);
    CHECK(f.data != NULL);
    size_t lead = 3000, n = lead + f.length + 500;
    float* x = (float*)calloc(n, sizeof(float));
    CHECK(x != NULL);
    memcpy(x + lead, f.data, f.length * sizeof(float));
    css_sync_result_t r;
    CHECK(css_detect_frame(NULL, n, &g, 3.0f, &r) == -1);
    CHECK(css_detect_frame(x, n, NULL, 3.0f, &r) == -1);
    CHECK(css_detect_frame(x, n, &g, 3.0f, NULL) == -1);
    CHECK(css_detect_frame(x, ((size_t)1 << 27) + 1, &g, 3.0f, &r) == -1); // too long
    CHECK(css_detect_frame(x, 10 * (size_t)g.N - 1, &g, 3.0f, &r) == 0);  // too short
    // Threshold: default for NaN / <= 0, capped for huge values.
    const float thr[] = {NAN, -1.0f, 0.0f, 1e30f, 0.5f};
    for (int i = 0; i < 5; i++) {
        CHECK(css_detect_frame(x, n, &g, thr[i], &r) == 1);
        CHECK(fabs(r.start - (double)lead) < 1.0 && r.rho > 0.9f && isfinite(r.snr_db));
    }
    size_t ob = 1;
    CHECK(css_demodulate(NULL, n, z, &ob) == NULL && ob == 0);
    CHECK(css_demodulate(x, n, z, NULL) == NULL);
    c = z;
    c.sf = 4;
    CHECK(css_demodulate(x, n, c, &ob) == NULL);
    // The preamble alone (no data symbol) yields nothing to decode.
    CHECK(css_demodulate(x, lead + 10 * (size_t)g.N, z, &ob) == NULL && ob == 0);

    // Non-finite and huge samples are treated as 0 / clamped, not propagated.
    x[lead + 10] = NAN;
    x[lead + 20] = INFINITY;
    x[lead + 30] = -INFINITY;
    uint8_t* out = css_demodulate(x, n, z, &ob);
    CHECK(out != NULL && ob >= 1 && out[0] == one);
    free(out);
    for (size_t i = 0; i < lead; i++) x[i] = (i % 2) ? 3e38f : -3e38f;
    out = css_demodulate(x, n, z, &ob); // must not crash; result unspecified
    free(out);
    CHECK(css_detect_frame(x, n, &g, 3.0f, &r) >= 0);

    // sync_detect_frame (mode 0) rejects a nonsense sample rate / SF.
    sync_config_t sc;
    memset(&sc, 0, sizeof sc);
    sc.sample_rate = NAN; // falls back to 44.1 kHz
    size_t st = 0;
    float snr = 0.0f;
    for (size_t i = 0; i < lead; i++) x[i] = 0.0f;
    CHECK(sync_detect_frame(x, n, &sc, &st, &snr) == 1 && st == lead);
    sc.sf = 3;
    CHECK(sync_detect_frame(x, n, &sc, &st, &snr) == 0);
    free(x);
    free(f.data);
    printf("PASS: CSS argument, config and input edge cases\n");
}

// Throughput table (computed from the geometry, printed for the docs).
static void print_rates(void) {
    const float bws[] = {2000.0f, 4000.0f};
    for (int b = 0; b < 2; b++)
        for (int sf = CSS_MIN_SF; sf <= CSS_MAX_SF; sf++) {
            sw_config_t c = css_cfg(sf, bws[b]);
            css_geometry_t g;
            CHECK(css_geometry(&c, &g) == 0);
            printf("  RATE B=%.0f SF%d: symbol %.2f ms, %.1f bit/s\n", g.B, sf,
                   1000.0 * g.N / g.fs, sf * g.B / g.M);
        }
}

int main(void) {
    printf("Running test_css...\n");
    test_legacy_raw_helpers();
    test_geometry();
    test_gray_adjacent();
    test_all_symbols();
    test_sync_offsets();
    test_preamble_like_payloads();
    test_no_false_alarm();
    test_ber_per_sf();
    test_frequency_offset();
    test_edge_cases();
    print_rates();
    printf("All CSS modulation & demodulation tests passed successfully!\n");
    return 0;
}
