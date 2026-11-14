// Fuzz target: the public FFI boundary (soundwave_api.h) as called from Dart.
//
// Every call receives a fuzzed sw_config_t (mostly realistic, sometimes
// hostile: negative sizes, NaN/Inf floats, huge values) and output buffers
// allocated at exactly the capacity the caller advertises. The API must
// validate everything it is given and never touch memory beyond those
// capacities.
//
// Structure-aware ops (modulate -> perturb -> demodulate) let the fuzzer reach
// deep demodulation paths that random samples rarely get past.

#include "fuzz_common.h"
#include "soundwave_api.h"

#define MAX_BITS    1024
#define MAX_SAMPLES (1u << 20) // 4 MiB of floats: caps modulator output

static void touch(const void* p, size_t n) {
    volatile uint8_t sink = 0;
    const uint8_t* b = (const uint8_t*)p;
    for (size_t i = 0; i < n; i++) sink ^= b[i];
    (void)sink;
}

static void op_crc_rs(fz_reader* r) {
    size_t n = fz_remaining(r);
    uint32_t crc = 0;
    FZ_CHECK(sw_crc32(r->data + r->pos, n, &crc) == SW_OK);
    uint8_t parity[32];
    size_t plen = sizeof parity;
    (void)sw_rs_encode(r->data + r->pos, n, parity, &plen);
}

// Modulate fuzzed bits with a fuzzed config into an exact-size buffer.
static float* modulate(fz_reader* r, sw_config_t cfg, size_t* out_len) {
    size_t nbits = 1 + fz_u16(r) % MAX_BITS;
    size_t nbytes = (nbits + 7) / 8;
    uint8_t* bits = (uint8_t*)malloc(nbytes);
    if (!bits) return NULL;
    for (size_t i = 0; i < nbytes; i++) bits[i] = fz_u8(r);

    // First call with a deliberately small capacity to exercise SW_ERR_OVERFLOW.
    size_t cap = fz_u16(r);
    float* samples = (float*)malloc((cap ? cap : 1) * sizeof(float));
    int (*mod)(const uint8_t*, size_t, sw_config_t, float*, size_t*) =
        cfg.modulation ? sw_ofdm_modulate : sw_css_modulate;
    size_t len = cap;
    int rc = samples ? mod(bits, nbits, cfg, samples, &len) : SW_ERR_MEMORY;
    if (rc == SW_OK) {
        FZ_CHECK(len <= cap);
    } else if (rc == SW_ERR_OVERFLOW && len > cap && len <= MAX_SAMPLES) {
        free(samples);
        cap = len;
        samples = (float*)malloc(cap * sizeof(float));
        rc = samples ? mod(bits, nbits, cfg, samples, &len) : SW_ERR_MEMORY;
        if (rc == SW_OK) FZ_CHECK(len <= cap);
    }
    free(bits);
    if (rc != SW_OK) {
        free(samples);
        return NULL;
    }
    *out_len = len;
    return samples;
}

static void demodulate(fz_reader* r, sw_config_t cfg, const float* s, size_t n) {
    size_t cap_bits = fz_u16(r);
    size_t cap_bytes = (cap_bits + 7) / 8;
    uint8_t* out = (uint8_t*)malloc(cap_bytes ? cap_bytes : 1);
    if (!out) return;
    size_t bit_len = cap_bits;
    int rc = cfg.modulation ? sw_ofdm_demodulate(s, n, cfg, out, &bit_len)
                            : sw_css_demodulate(s, n, cfg, out, &bit_len);
    if (rc == SW_OK) {
        FZ_CHECK(bit_len <= cap_bits);
        touch(out, (bit_len + 7) / 8);
    }
    free(out);

    // Equalized constellation points, at a fuzz-chosen capacity.
    size_t cap_pts = 1 + fz_u16(r) % 4096;
    float* iq = (float*)malloc(2 * cap_pts * sizeof(float));
    if (iq) {
        size_t pts = cap_pts;
        if (sw_ofdm_equalized_symbols(s, n, cfg, iq, &pts) == SW_OK) {
            FZ_CHECK(pts <= cap_pts);
            touch(iq, 2 * pts * sizeof(float));
        }
        free(iq);
    }

    size_t start = 0;
    float snr = 0.0f, cfo = 0.0f;
    if (sw_detect_frame(s, n, cfg, &start, &snr) == SW_OK) FZ_CHECK(start < n);
    (void)sw_estimate_cfo(s, n, cfg, &cfo);
}

static void op_roundtrip(fz_reader* r) {
    sw_config_t cfg = fz_config(r);
    size_t n = 0;
    float* s = modulate(r, cfg, &n);
    if (!s) return;
    // Perturb: scale, overwrite a window with fuzz-controlled floats.
    float gain = (float)(fz_u8(r) + 1) / 64.0f;
    for (size_t i = 0; i < n; i++) s[i] *= gain;
    size_t at = n ? fz_u32(r) % n : 0;
    while (fz_remaining(r) >= 4 && at < n) {
        uint32_t v = fz_u32(r);
        memcpy(&s[at++], &v, sizeof v);
    }
    demodulate(r, cfg, s, n);
    free(s);
}

static void op_raw_samples(fz_reader* r) {
    sw_config_t cfg = fz_config(r);
    size_t n = 0;
    float* s = fz_floats(r, 65536, &n);
    if (!s) return;
    demodulate(r, cfg, s, n);
    free(s);
}

static void op_null_and_degenerate(fz_reader* r) {
    sw_config_t cfg = fz_config(r);
    float f = 0.0f;
    uint8_t b = 0;
    size_t len = 0, start = 0;
    float snr = 0.0f;
    uint32_t crc = 0;
    int fixed = 0;
    FZ_CHECK(sw_crc32(NULL, 4, &crc) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_rs_decode(NULL, &len, &b, 1, &fixed) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_css_modulate(NULL, 8, cfg, &f, &len) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_ofdm_modulate(&b, 8, cfg, NULL, &len) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_css_demodulate(&f, 1, cfg, NULL, &len) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_ofdm_demodulate(NULL, 1, cfg, &b, &len) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_ofdm_equalized_symbols(NULL, 1, cfg, &f, &len) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_detect_frame(&f, 1, cfg, NULL, &snr) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_estimate_cfo(&f, 1, cfg, NULL) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_audio_capture_stop(NULL) == SW_ERR_BAD_PARAM);
    FZ_CHECK(sw_audio_playback_stop(NULL) == SW_ERR_BAD_PARAM);
    // One-sample inputs must be handled without reading past the sample.
    (void)sw_detect_frame(&f, 1, cfg, &start, &snr);
    (void)sw_estimate_cfo(&f, 1, cfg, &snr);
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    fz_reader r;
    fz_init(&r, data, size);
    switch (fz_u8(&r) % 4) {
    case 0: op_crc_rs(&r); break;
    case 1: op_roundtrip(&r); break;
    case 2: op_raw_samples(&r); break;
    default: op_null_and_degenerate(&r); break;
    }
    return 0;
}
