// Fuzz target: OFDM demodulation (internal entry point + FFI wrapper).
// Property: no crash, no OOB, no leak; outputs stay within advertised sizes.

#include "fuzz_common.h"
#include "soundwave/ofdm.h"
#include "soundwave_api.h"

#define MAX_SAMPLES 32768

static void fuzz_internal(fz_reader* r) {
    static const int sizes[] = {64, 128, 256};
    int N = sizes[fz_u8(r) % 3];
    ofdm_config_t cfg = {
        .num_subcarriers = N,
        .cp_length = N / (4 << (fz_u8(r) % 3)), // N/4, N/8, N/16
        .modulation = fz_u8(r) & 1,
        .num_pilots = 8,
        .pilot_boost = 3.0f,
        .pilot_spacing = 6,
    };
    ofdm_init(&cfg);
    size_t n = 0;
    float* s = fz_floats(r, MAX_SAMPLES, &n);
    if (!s) return;
    size_t out_len = 0;
    uint8_t* bits = NULL;
    if (ofdm_demodulate_frame(s, n, &cfg, &bits, &out_len) == SW_OK) {
        volatile uint8_t sink = 0;
        for (size_t i = 0; i < (out_len + 7) / 8; i++) sink ^= bits[i];
        (void)sink;
        free(bits);
    }
    free(s);
}

static void fuzz_api(fz_reader* r) {
    sw_config_t cfg = fz_config(r);
    cfg.modulation = 1;
    size_t cap_bits = fz_u16(r);
    size_t n = 0;
    float* s = fz_floats(r, MAX_SAMPLES, &n);
    if (!s) return;
    size_t cap_bytes = (cap_bits + 7) / 8;
    uint8_t* out = (uint8_t*)malloc(cap_bytes ? cap_bytes : 1);
    if (out) {
        size_t bit_len = cap_bits;
        int rc = sw_ofdm_demodulate(s, n, cfg, out, &bit_len);
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
