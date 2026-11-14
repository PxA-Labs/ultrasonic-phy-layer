// OFDM band plan and transmit spectrum (ultrasonic band confinement).
//
// The OFDM modulator must put its energy into the configured band
// [carrier - bw/2, carrier + bw/2] (default 18-20 kHz) and keep the audible
// range quiet. This test modulates a typical frame through the public API,
// takes the periodogram of the whole frame (zero-padded FFT, so Parseval
// holds exactly) and checks:
//
//   * >= 98.5 % of the energy lies inside the configured band. The rest is
//     the main lobe of the two outermost subcarriers: a symbol of
//     T = (N + cp) / fs has a sinc^2 spectrum with first nulls at +-1/T, and
//     the outermost active bin sits one subcarrier spacing (fs/N, slightly
//     more than 1/T) inside each band edge, so ~1 % of the energy lands
//     within a few hundred Hz outside the band (still above 17.5 kHz).
//   * <= -40 dB of the energy below 16 kHz (audible to most adults) and
//     <= -30 dB below 17 kHz. Without transmit windowing the sinc sidelobes
//     of the symbol-boundary discontinuities alone leave about -26 dB below
//     16 kHz; the raised-cosine cross-fade (OFDM_WOLA_LEN = cp / 2) and the
//     phase-continuous preamble junction bring it to about -43 dB or lower.
//   * every bin outside the active range is exactly empty in each symbol's
//     FFT window (DC, audible bins, Nyquist), and the band plan is validated.
//
// Uses CHECK instead of assert() so it also runs in Release (NDEBUG) builds.

#include "soundwave_api.h"
#include "soundwave/ofdm.h"
#include "kiss_fft.h"
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

#define MIN_INBAND_FRACTION 0.985
#define MAX_BELOW_16K_DB    (-40.0)
#define MAX_BELOW_17K_DB    (-30.0)
#define FRAME_BYTES         46 // CRC-32 + 10-byte payload + RS(32) parity

static sw_config_t ofdm_cfg(int N, int cp, float carrier, float bw) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100;
    c.modulation = 1;
    c.num_subcarriers = N;
    c.cp_length = cp;
    c.num_pilots = 8;
    c.threshold = 3.0f;
    c.carrier_freq = carrier;
    c.bandwidth = bw;
    c.amplitude = 0.8f;
    c.ofdm_modulation = 1; // QPSK
    return c;
}

static float* modulate(sw_config_t cfg, size_t* len) {
    uint8_t frame[FRAME_BYTES];
    uint32_t x = 0x1234567u;
    for (int i = 0; i < FRAME_BYTES; i++) {
        x = x * 1664525u + 1013904223u;
        frame[i] = (uint8_t)(x >> 24);
    }
    size_t cap = 0;
    float dummy = 0.0f;
    if (sw_ofdm_modulate(frame, sizeof frame * 8, cfg, &dummy, &cap) != SW_ERR_OVERFLOW)
        return NULL;
    float* s = (float*)malloc(cap * sizeof(float));
    if (!s) return NULL;
    *len = cap;
    if (sw_ofdm_modulate(frame, sizeof frame * 8, cfg, s, len) != SW_OK) {
        free(s);
        return NULL;
    }
    return s;
}

static void check_spectrum(int N, int cp, float carrier, float bw) {
    sw_config_t cfg = ofdm_cfg(N, cp, carrier, bw);
    size_t len = 0;
    float* s = modulate(cfg, &len);
    CHECK(s != NULL);
    if (!s) return;

    ofdm_layout_t lay;
    CHECK(ofdm_layout_compute(N, 44100.0f, carrier, bw, &lay) == SW_OK);
    size_t L = (size_t)N + (size_t)cp;
    size_t S = (FRAME_BYTES * 8 + (size_t)(2 * lay.num_data) - 1) / (size_t)(2 * lay.num_data);
    CHECK(len == (2 + S) * L + (size_t)OFDM_WOLA_LEN(cp));

    // Periodogram of the whole frame.
    int M = 1;
    while ((size_t)M < 2 * len) M <<= 1;
    kiss_fft_cpx* in = (kiss_fft_cpx*)calloc((size_t)M, sizeof(kiss_fft_cpx));
    kiss_fft_cpx* out = (kiss_fft_cpx*)malloc((size_t)M * sizeof(kiss_fft_cpx));
    kiss_fft_cfg fft = kiss_fft_alloc(M, 0, NULL, NULL);
    CHECK(in && out && fft);
    if (in && out && fft) {
        float peak = 0.0f;
        for (size_t n = 0; n < len; n++) {
            in[n].r = s[n];
            if (fabsf(s[n]) > peak) peak = fabsf(s[n]);
        }
        kiss_fft(fft, in, out);
        double f_lo = (double)carrier - 0.5 * (double)bw;
        double f_hi = (double)carrier + 0.5 * (double)bw;
        double total = 0.0, inband = 0.0, below16 = 0.0, below17 = 0.0;
        for (int k = 0; k <= M / 2; k++) {
            double p = (double)out[k].r * out[k].r + (double)out[k].i * out[k].i;
            double f = (double)k * 44100.0 / (double)M;
            total += p;
            if (f >= f_lo && f <= f_hi) inband += p;
            if (f < 16000.0) below16 += p;
            if (f < 17000.0) below17 += p;
        }
        double frac = inband / total;
        double db16 = 10.0 * log10(below16 / total + 1e-30);
        double db17 = 10.0 * log10(below17 / total + 1e-30);
        printf("N=%4d cp=%3d band %5.0f-%5.0f Hz: bins %d..%d (%d data), %zu samples, "
               "in band %.2f %%, <16 kHz %.1f dB, <17 kHz %.1f dB, peak %.2f\n",
               N, cp, f_lo, f_hi, lay.first_bin, lay.last_bin, lay.num_data, len,
               100.0 * frac, db16, db17, peak);
        CHECK(frac >= MIN_INBAND_FRACTION);
        CHECK(db16 <= MAX_BELOW_16K_DB);
        CHECK(db17 <= MAX_BELOW_17K_DB);
    }
    free(in);
    free(out);
    free(fft);

    // Every symbol's FFT window holds energy on the active bins only.
    kiss_fft_cpx* Y = (kiss_fft_cpx*)malloc((size_t)N * sizeof(kiss_fft_cpx));
    CHECK(Y != NULL);
    if (Y) {
        int off = cp - OFDM_TIMING_BACKOFF(cp);
        double worst = 0.0, active_min = INFINITY;
        for (size_t sym = 0; sym < 2 + S; sym++) {
            ofdm_dft_demodulate(s + sym * L, N, off, Y);
            for (int k = 0; k <= N / 2; k++) {
                double m = sqrt((double)Y[k].r * Y[k].r + (double)Y[k].i * Y[k].i);
                if (k < lay.first_bin || k > lay.last_bin) {
                    if (m > worst) worst = m;
                } else if (m < active_min) {
                    active_min = m;
                }
            }
        }
        // Active bins carry unit-magnitude symbols; float32 IFFT/FFT
        // round-off leaves ~1e-6 elsewhere.
        CHECK(worst < 1e-4);
        CHECK(active_min > 0.99);
    }
    free(Y);
    free(s);
}

static void test_band_plan_and_validation(void) {
    ofdm_layout_t lay;
    // Defaults (0) = 19 kHz +- 1 kHz at 44.1 kHz.
    CHECK(ofdm_layout_compute(256, 0.0f, 0.0f, 0.0f, &lay) == SW_OK);
    CHECK(lay.first_bin == 106 && lay.last_bin == 115);
    CHECK(lay.num_pilots == 2 && lay.num_data == 8);
    // First and last active subcarrier inside the band, one bin of guard.
    double df = 44100.0 / 256.0;
    CHECK(lay.first_bin * df >= 18000.0 + df && lay.last_bin * df <= 20000.0 - df);

    sw_config_t ok = ofdm_cfg(256, 32, 19000.0f, 2000.0f);
    CHECK(sw_config_validate(ok) == SW_OK);
    sw_config_t zero;
    memset(&zero, 0, sizeof zero);
    zero.modulation = 1;
    CHECK(sw_config_validate(zero) == SW_OK); // all defaults

    float s[16];
    size_t n = 16;
    uint8_t b[4] = {1, 2, 3, 4};
    struct { float carrier, bw; const char* why; } bad[] = {
        {21500.0f, 2000.0f, "band above Nyquist"},
        {21000.0f, 2000.0f, "no subcarrier of guard below Nyquist"},
        {19000.0f, 500.0f, "fewer than 4 subcarriers"},
        {500.0f, 2000.0f, "band reaches DC"},
        {19000.0f, NAN, "non-finite bandwidth"},
    };
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++) {
        sw_config_t c = ofdm_cfg(256, 32, bad[i].carrier, bad[i].bw);
        int v = sw_config_validate(c);
        n = 16;
        int m = sw_ofdm_modulate(b, 32, c, s, &n);
        if (v != SW_ERR_BAD_PARAM || m != SW_ERR_BAD_PARAM)
            fprintf(stderr, "band case '%s' not rejected (%d, %d)\n", bad[i].why, v, m);
        CHECK(v == SW_ERR_BAD_PARAM);
        CHECK(m == SW_ERR_BAD_PARAM);
        // The OFDM entry points reject the band even if the struct says CSS.
        c.modulation = 0;
        n = 16;
        CHECK(sw_ofdm_modulate(b, 32, c, s, &n) == SW_ERR_BAD_PARAM);
    }
    // A CSS config with the same values is not affected by the OFDM band plan.
    sw_config_t css = ofdm_cfg(256, 32, 21000.0f, 2000.0f);
    css.modulation = 0;
    CHECK(sw_config_validate(css) == SW_OK);
}

int main(void) {
    test_band_plan_and_validation();
    check_spectrum(256, 32, 19000.0f, 2000.0f);
    check_spectrum(256, 64, 19000.0f, 2000.0f); // app / CLI default
    check_spectrum(512, 64, 19000.0f, 2000.0f);
    check_spectrum(1024, 128, 19000.0f, 2000.0f);
    check_spectrum(2048, 128, 19000.0f, 2000.0f);
    check_spectrum(256, 64, 19500.0f, 3000.0f);  // 18-21 kHz
    check_spectrum(2048, 128, 19500.0f, 3000.0f); // app "High Speed" preset
    if (failures) {
        fprintf(stderr, "%d OFDM spectrum check(s) failed\n", failures);
        return 1;
    }
    printf("All OFDM band/spectrum tests passed.\n");
    return 0;
}
