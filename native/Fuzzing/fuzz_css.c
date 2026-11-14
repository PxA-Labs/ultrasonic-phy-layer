// Fuzz target: CSS demodulation (internal entry point + FFI wrapper) and the
// SF-bit symbol path (modulate -> perturb -> sync -> demodulate).
// Raw float samples include NaN/Inf/huge values; configs include hostile ones.
// Property: no crash, no OOB, no leak; outputs stay within advertised sizes;
// an unperturbed frame decodes to exactly the bits that were sent.

#include "fuzz_common.h"
#include "soundwave/css.h"
#include "soundwave/sync.h"
#include "soundwave_api.h"

#define MAX_SAMPLES 32768
#define MAX_RT_BITS 64

// Internal entry point with the configs the module accepts at its edges:
// every SF (and one past the maximum), several bandwidths.
static void fuzz_internal(fz_reader* r) {
    static const float bws[] = {1000.0f, 2000.0f, 4000.0f, 8000.0f};
    sw_config cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.sample_rate = 44100;
    cfg.sf = CSS_MIN_SF + fz_u8(r) % (CSS_MAX_SF - CSS_MIN_SF + 2);
    cfg.bandwidth = bws[fz_u8(r) % 4];
    cfg.carrier_freq = 18000.0f;
    size_t n = 0;
    float* s = fz_floats(r, MAX_SAMPLES, &n);
    if (!s) return;
    size_t out_bytes = 0;
    uint8_t* bits = css_demodulate(s, n, cfg, &out_bytes);
    if (bits) {
        volatile uint8_t sink = 0;
        for (size_t i = 0; i < out_bytes; i++) sink ^= bits[i]; // touch every byte
        (void)sink;
    }
    free(bits);
    free(s);
}

static void fuzz_api(fz_reader* r) {
    sw_config_t cfg = fz_config(r);
    cfg.modulation = 0;
    size_t cap_bits = fz_u16(r);
    size_t n = 0;
    float* s = fz_floats(r, MAX_SAMPLES, &n);
    if (!s) return;
    size_t cap_bytes = (cap_bits + 7) / 8;
    uint8_t* out = (uint8_t*)malloc(cap_bytes ? cap_bytes : 1);
    if (out) {
        size_t bit_len = cap_bits;
        int rc = sw_css_demodulate(s, n, cfg, out, &bit_len);
        if (rc == SW_OK) FZ_CHECK(bit_len <= cap_bits);
        free(out);
    }
    free(s);
}

// Every SF: modulate fuzzed bits behind a fuzzed lead-in, optionally perturb,
// then detect + demodulate. Clean frames must round-trip exactly.
static void fuzz_roundtrip(fz_reader* r) {
    sw_config_t cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.sample_rate = (fz_u8(r) & 1) ? 48000 : 44100;
    cfg.sf = CSS_MIN_SF + fz_u8(r) % (CSS_MAX_SF - CSS_MIN_SF + 1);
    cfg.bandwidth = cfg.sf >= 9 ? 4000.0f : ((fz_u8(r) & 1) ? 4000.0f : 2000.0f);
    cfg.carrier_freq = 19000.0f;
    cfg.amplitude = 0.8f;
    cfg.threshold = 3.0f;
    css_geometry_t g;
    FZ_CHECK(css_geometry(&cfg, &g) == 0);

    size_t nbits = 1 + fz_u8(r) % MAX_RT_BITS;
    uint8_t bits[MAX_RT_BITS / 8];
    memset(bits, 0, sizeof bits);
    for (size_t i = 0; i < (nbits + 7) / 8; i++) bits[i] = fz_u8(r);
    size_t lead = fz_u16(r) % (2 * (size_t)g.N);
    size_t frame = css_frame_samples(&g, nbits);
    FZ_CHECK(frame > 0);
    size_t n = lead + frame + (size_t)g.N / 2;
    float* s = (float*)calloc(n, sizeof(float));
    if (!s) return;
    css_modulate_into(&g, bits, nbits, s + lead);

    int perturb = fz_u8(r) & 1;
    if (perturb) {
        size_t at = fz_u32(r) % n;
        while (fz_remaining(r) >= 4 && at < n) {
            uint32_t v = fz_u32(r);
            memcpy(&s[at++], &v, sizeof v); // may be NaN/Inf: intended
        }
    }

    css_sync_result_t res;
    int found = css_detect_frame(s, n, &g, cfg.threshold, &res);
    FZ_CHECK(found >= 0);
    if (found == 1) FZ_CHECK(res.start >= 0.0 && res.start < (double)n);

    size_t out_bytes = 0;
    uint8_t* out = css_demodulate(s, n, cfg, &out_bytes);
    if (!perturb) {
        FZ_CHECK(found == 1);
        FZ_CHECK(res.start > (double)lead - 1.0 && res.start < (double)lead + 1.0);
        FZ_CHECK(out != NULL && out_bytes * 8 >= nbits);
        for (size_t i = 0; i < nbits; i++) {
            int a = (bits[i / 8] >> (7 - i % 8)) & 1;
            int b = (out[i / 8] >> (7 - i % 8)) & 1;
            FZ_CHECK(a == b);
        }
    }
    free(out);
    free(s);
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    fz_reader r;
    fz_init(&r, data, size);
    switch (fz_u8(&r) % 3) {
    case 0: fuzz_internal(&r); break;
    case 1: fuzz_api(&r); break;
    default: fuzz_roundtrip(&r); break;
    }
    return 0;
}
