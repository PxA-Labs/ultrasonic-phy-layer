// TEMPORARY diagnostic for the OFDM equalizer EVM investigation. Prints
// analytic-signal, timing and per-subcarrier equalizer data, then fails on
// purpose so ctest --output-on-failure shows the output. Not for merge.

#include "soundwave_api.h"
#include "soundwave/cfo.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SAMPLES (1u << 17)
#define MAX_POINTS 8192

static sw_config_t cfg_of(int mod, int cp) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100; c.modulation = 1; c.sf = 8;
    c.num_subcarriers = 256; c.cp_length = cp; c.num_pilots = 16;
    c.coding_rate = 0.5f; c.threshold = 3.0f; c.equalizer = 0;
    c.carrier_freq = 19000.0f; c.bandwidth = 2000.0f;
    c.symbol_duration = 0.02f; c.amplitude = 0.8f; c.ofdm_modulation = mod;
    return c;
}

static double ref_dist(double r, double i, int mod, double* er, double* ei) {
    const double q = 0.70710678;
    double rr = mod == 0 ? (r >= 0 ? 1.0 : -1.0) : (r >= 0 ? q : -q);
    double ri = mod == 0 ? 0.0 : (i >= 0 ? q : -q);
    if (er) *er = rr;
    if (ei) *ei = ri;
    return (r - rr) * (r - rr) + (i - ri) * (i - ri);
}

static void run(int mod, int cp, size_t lead) {
    uint8_t payload[32];
    for (int i = 0; i < 32; i++) payload[i] = (uint8_t)(i * 37 + 11);
    sw_config_t c = cfg_of(mod, cp);
    float* s = (float*)calloc(MAX_SAMPLES, sizeof(float));
    size_t len = MAX_SAMPLES - lead;
    if (sw_ofdm_modulate(payload, sizeof payload * 8, c, s + lead, &len) != SW_OK) {
        printf("modulate failed\n"); free(s); return;
    }
    size_t L = 256 + (size_t)cp;
    size_t n = lead + len + L - 1;

    // Analytic signal: Re{z} must equal x.
    float* ar = (float*)malloc(n * sizeof(float));
    float* ai = (float*)malloc(n * sizeof(float));
    sync_real_to_analytic(s, n, ar, ai);
    double ex = 0, e_re = 0, e_model = 0;
    for (size_t k = 0; k < n; k++) {
        double x = s[k], xr = s[(n - k) % n];
        ex += x * x;
        e_re += (ar[k] - x) * (ar[k] - x);
        double m = 0.75 * x + 0.25 * xr;
        e_model += (ar[k] - m) * (ar[k] - m);
    }
    printf("[%s cp=%d lead=%zu] n=%zu  rms(Re z - x)/rms(x)=%.3e  "
           "rms(Re z - (0.75x[n]+0.25x[-n]))/rms(x)=%.3e\n",
           mod ? "QPSK" : "BPSK", cp, lead, n, sqrt(e_re / ex), sqrt(e_model / ex));

    size_t start = 0; float snr = 0;
    int rc = sw_detect_frame(s, n, c, &start, &snr);
    printf("  detect rc=%d start=%zu (true %zu) snr=%.1f dB\n", rc, start, lead, snr);

    float* iq = (float*)malloc(2 * MAX_POINTS * sizeof(float));
    size_t count = MAX_POINTS;
    rc = sw_ofdm_equalized_symbols(s, n, c, iq, &count);
    const size_t nd = 83;
    double tot = 0;
    for (size_t k = 0; k < count; k++) tot += ref_dist(iq[2*k], iq[2*k+1], mod, NULL, NULL);
    printf("  eq rc=%d points=%zu EVM=%.3f%%\n", rc, count, count ? 100 * sqrt(tot / count) : -1.0);
    for (size_t sym = 0; sym * nd < count; sym++) {
        double e = 0; size_t m = 0;
        for (size_t d = 0; d < nd && sym * nd + d < count; d++, m++) {
            size_t k = sym * nd + d;
            e += ref_dist(iq[2*k], iq[2*k+1], mod, NULL, NULL);
        }
        printf("  symbol %zu EVM=%.3f%%\n", sym, 100 * sqrt(e / (double)m));
    }
    // Per-subcarrier error of the first data symbol (data index d).
    printf("  sym0 per data subcarrier: d: |x|/|ref|, phase err deg\n   ");
    for (size_t d = 0; d < nd && d < count; d += 4) {
        double rr, ri;
        ref_dist(iq[2*d], iq[2*d+1], mod, &rr, &ri);
        double mag = sqrt(iq[2*d]*iq[2*d] + iq[2*d+1]*iq[2*d+1]) / sqrt(rr*rr + ri*ri);
        double ph = (atan2(iq[2*d+1], iq[2*d]) - atan2(ri, rr)) * 180.0 / 3.14159265358979;
        if (ph > 180) ph -= 360;
        if (ph < -180) ph += 360;
        printf(" %zu:%.3f,%+.1f", d, mag, ph);
    }
    printf("\n");
    free(iq); free(ar); free(ai); free(s);
}

int main(void) {
    run(1, 32, 0);
    run(1, 64, 0);
    run(0, 32, 0);
    run(0, 64, 0);
    run(1, 32, 37);
    run(0, 64, 37);
    printf("DIAGNOSTIC: intentional failure so ctest prints this output.\n");
    return 1;
}
