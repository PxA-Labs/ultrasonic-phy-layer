// Shared helpers for fuzz harnesses: a bounds-checked byte reader that turns
// raw fuzzer input into structured values (configs, sample buffers).
//
// The reader never reads past `size`; once exhausted every getter returns 0,
// so harnesses stay deterministic for a given input.

#ifndef SOUNDWAVE_FUZZ_COMMON_H
#define SOUNDWAVE_FUZZ_COMMON_H

#include "soundwave/types.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const uint8_t* data;
    size_t size;
    size_t pos;
} fz_reader;

static inline void fz_init(fz_reader* r, const uint8_t* data, size_t size) {
    r->data = data;
    r->size = size;
    r->pos = 0;
}

static inline size_t fz_remaining(const fz_reader* r) { return r->size - r->pos; }

static inline uint8_t fz_u8(fz_reader* r) {
    return (r->pos < r->size) ? r->data[r->pos++] : 0;
}

static inline uint16_t fz_u16(fz_reader* r) {
    uint16_t hi = fz_u8(r);
    return (uint16_t)((hi << 8) | fz_u8(r));
}

static inline uint32_t fz_u32(fz_reader* r) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) v = (v << 8) | fz_u8(r);
    return v;
}

// Pick one entry of a small table; ~1/16 of the time return a raw 32-bit
// value instead so API validation sees hostile out-of-range numbers too.
static inline int fz_pick_int(fz_reader* r, const int* table, size_t n) {
    uint8_t sel = fz_u8(r);
    if ((sel & 0x0F) == 0x0F) return (int)fz_u32(r);
    return table[sel % n];
}

static inline float fz_pick_float(fz_reader* r, const float* table, size_t n) {
    uint8_t sel = fz_u8(r);
    if ((sel & 0x0F) == 0x0F) {
        uint32_t bits = fz_u32(r);
        float f;
        memcpy(&f, &bits, sizeof f); // may be NaN/Inf/denormal: intended
        return f;
    }
    return table[sel % n];
}

// Build an sw_config_t mostly from realistic values, occasionally hostile.
static inline sw_config_t fz_config(fz_reader* r) {
    static const int   rates[]    = {0, 8000, 16000, 22050, 44100, 48000, 96000};
    static const int   sfs[]      = {0, 6, 7, 8, 9, 10, 11, 12};
    static const int   subcars[]  = {0, 16, 32, 64, 128, 256, 512};
    static const int   cps[]      = {0, 4, 8, 16, 32, 64};
    static const int   pilots[]   = {0, 2, 4, 8, 16};
    static const float carriers[] = {0.0f, 17000.0f, 18000.0f, 19000.0f, 20000.0f};
    static const float bws[]      = {0.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f};
    static const float durs[]     = {0.0f, 0.005f, 0.01f, 0.02f, 0.05f};
    static const float amps[]     = {0.0f, 0.5f, 0.8f, 1.0f};
    static const float threshs[]  = {0.0f, 1.0f, 3.0f, 6.0f};

    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.modulation      = fz_u8(r) & 1;
    c.sample_rate     = fz_pick_int(r, rates, sizeof rates / sizeof *rates);
    c.sf              = fz_pick_int(r, sfs, sizeof sfs / sizeof *sfs);
    c.num_subcarriers = fz_pick_int(r, subcars, sizeof subcars / sizeof *subcars);
    c.cp_length       = fz_pick_int(r, cps, sizeof cps / sizeof *cps);
    c.num_pilots      = fz_pick_int(r, pilots, sizeof pilots / sizeof *pilots);
    c.carrier_freq    = fz_pick_float(r, carriers, sizeof carriers / sizeof *carriers);
    c.bandwidth       = fz_pick_float(r, bws, sizeof bws / sizeof *bws);
    c.symbol_duration = fz_pick_float(r, durs, sizeof durs / sizeof *durs);
    c.amplitude       = fz_pick_float(r, amps, sizeof amps / sizeof *amps);
    c.threshold       = fz_pick_float(r, threshs, sizeof threshs / sizeof *threshs);
    c.equalizer       = fz_u8(r) & 1;
    c.ofdm_modulation = fz_u8(r) & 1;
    c.coding_rate     = 0.5f;
    return c;
}

// Copy the remaining bytes into a freshly allocated float buffer (exact size,
// so any overread is caught by ASan / Guard Malloc). Returns NULL when fewer
// than 4 bytes remain. Caller frees.
static inline float* fz_floats(fz_reader* r, size_t max_count, size_t* count) {
    size_t n = fz_remaining(r) / sizeof(float);
    if (n > max_count) n = max_count;
    *count = n;
    if (n == 0) return NULL;
    float* buf = (float*)malloc(n * sizeof(float));
    if (!buf) return NULL;
    memcpy(buf, r->data + r->pos, n * sizeof(float));
    r->pos += n * sizeof(float);
    return buf;
}

// Property violation: abort so libFuzzer / CTest records a crash.
#define FZ_CHECK(cond)                                                        \
    do {                                                                      \
        if (!(cond)) {                                                        \
            fprintf(stderr, "FUZZ PROPERTY VIOLATED: %s (%s:%d)\n", #cond,    \
                    __FILE__, __LINE__);                                      \
            abort();                                                          \
        }                                                                     \
    } while (0)

#endif // SOUNDWAVE_FUZZ_COMMON_H
