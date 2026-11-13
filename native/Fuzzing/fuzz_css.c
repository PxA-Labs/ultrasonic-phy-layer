// Fuzz target: CSS demodulation (internal entry point + FFI wrapper).
// Raw float samples include NaN/Inf/huge values; configs include hostile ones.
// Property: no crash, no OOB, no leak; outputs stay within advertised sizes.

#include "fuzz_common.h"
#include "soundwave/css.h"
#include "soundwave_api.h"

#define MAX_SAMPLES 32768

static void fuzz_internal(fz_reader* r) {
    css_config_t cfg = {
        .sf = 7 + fz_u8(r) % 4, // 7..10: valid range for the internal API
        .bandwidth = 2000.0f,
        .sample_rate = 44100.0f,
        .f0 = 18000.0f,
    };
    css_init(&cfg);
    size_t n = 0;
    float* s = fz_floats(r, MAX_SAMPLES, &n);
    if (!s) return;
    size_t out_bytes = 0;
    uint8_t* bits = css_demodulate_frame(s, n, &cfg, &out_bytes);
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

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    fz_reader r;
    fz_init(&r, data, size);
    if (fz_u8(&r) & 1) fuzz_internal(&r); else fuzz_api(&r);
    return 0;
}
