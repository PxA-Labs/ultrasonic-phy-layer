// Regression tests for memory-safety and correctness bugs found by the
// sanitizer/fuzzing work in issue #28. Each case names the defect it pins.
// Most cases are only meaningful under ASan/UBSan (they used to read or write
// out of bounds), but all of them also assert the corrected behaviour.

#include "soundwave_api.h"
#include "soundwave/cfo.h"
#include "soundwave/fec.h"
#include "soundwave/packet.h"
#include "soundwave/rs.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Always-on check: CI's dsp-core job builds Release (NDEBUG), where CHECK()
// and every call inside it would be compiled out and the test would pass
// without checking anything.
#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "CHECK failed: %s (%s:%d)\n", #cond, __FILE__,     \
                    __LINE__);                                                 \
            exit(1);                                                           \
        }                                                                      \
    } while (0)

static sw_config_t default_cfg(int modulation) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100;
    c.modulation = modulation;
    c.sf = 8;
    c.num_subcarriers = 256;
    c.cp_length = 32;
    c.num_pilots = 16;
    c.carrier_freq = 19000.0f;
    c.bandwidth = 2000.0f;
    c.symbol_duration = 0.02f;
    c.amplitude = 0.8f;
    c.threshold = 3.0f;
    return c;
}

// RS(63,31): shortened RS(k+32,k) with k = 31 has n = 63, which rs_decode()
// mistook for RS(63,47) (16 parity) -> 9..16 errors were not corrected.
static void test_rs_k31_uses_32_parity(void) {
    uint8_t msg[31], data[31], parity[32];
    for (int i = 0; i < 31; i++) msg[i] = data[i] = (uint8_t)(i * 7 + 3);
    size_t plen = sizeof parity;
    CHECK(sw_rs_encode(data, 31, parity, &plen) == SW_OK && plen == 32);
    for (int e = 0; e < 16; e++) data[e] ^= 0x5A; // t = 16 errors
    size_t dlen = 31;
    int fixed = -1;
    CHECK(sw_rs_decode(data, &dlen, parity, plen, &fixed) == SW_OK);
    CHECK(fixed == 16);
    CHECK(memcmp(data, msg, 31) == 0);
    printf("PASS: RS k=31 corrects 16 errors with explicit parity count\n");
}

// sw_rs_decode computed k + parity_len without overflow checks.
static void test_rs_decode_rejects_hostile_lengths(void) {
    uint8_t data[4] = {1, 2, 3, 4}, parity[32] = {0};
    size_t dlen = 4;
    int fixed = 0;
    CHECK(sw_rs_decode(data, &dlen, parity, SIZE_MAX, &fixed) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_decode(data, &dlen, parity, 0, &fixed) == SW_ERR_BAD_PARAM);
    dlen = 300;
    CHECK(sw_rs_decode(data, &dlen, parity, 32, &fixed) == SW_ERR_BAD_PARAM);
    printf("PASS: sw_rs_decode rejects overflowing lengths\n");
}

// Packet length field is one byte: 256-byte payloads encoded as length 0.
// header_len < 2 made packet_encode memset with a wrapped (huge) length.
static void test_packet_limits(void) {
    packet_config_t cfg;
    packet_init(&cfg);
    CHECK(cfg.max_payload == 255);
    uint8_t payload[256], frame[512], out[256];
    for (int i = 0; i < 256; i++) payload[i] = (uint8_t)i;
    size_t flen = 0, olen = 0;
    CHECK(packet_encode(&cfg, payload, 255, frame, sizeof frame, &flen) == 0);
    CHECK(packet_decode(&cfg, frame, flen, out, sizeof out, &olen) == 0);
    CHECK(olen == 255 && memcmp(out, payload, 255) == 0);
    CHECK(packet_encode(&cfg, payload, 256, frame, sizeof frame, &flen) == -1);

    packet_config_t bad = cfg;
    bad.header_len = 1;
    CHECK(packet_encode(&bad, payload, 4, frame, sizeof frame, &flen) == -1);
    CHECK(packet_decode(&bad, frame, flen, out, sizeof out, &olen) == -1);
    bad = cfg;
    bad.preamble_len = -5;
    CHECK(packet_decode(&bad, frame, flen, out, sizeof out, &olen) == -1);
    printf("PASS: packet framing enforces 255-byte payload and sane config\n");
}

// fec_encode dropped the data bytes (only parity reached the codeword) and the
// interleaver covered 204/255 positions, leaving uninitialised bytes.
static void test_fec_round_trip(void) {
    size_t lens[] = {0, 1, 100, 223};
    for (size_t t = 0; t < sizeof lens / sizeof *lens; t++) {
        size_t k = lens[t];
        uint8_t msg[223] = {0}, coded[255], out[223];
        for (size_t i = 0; i < k; i++) msg[i] = (uint8_t)(i ^ 0xA5);
        size_t clen = 0, olen = 0;
        int fixed = -1;
        CHECK(fec_encode(msg, k, coded, &clen) == 0 && clen == 255);
        for (int e = 0; e < 16; e++) coded[e * 15] ^= 0xFF; // 16 symbol errors
        CHECK(fec_decode(coded, clen, out, &olen, &fixed) == 16);
        CHECK(fixed == 16 && olen == 223);
        CHECK(k == 0 || memcmp(out, msg, k) == 0);
    }
    printf("PASS: FEC encode/decode round trip with 16 errors\n");
}

// sync_schmidl_cox_cfo read y[n + N] past the buffer when len < 2N and divided
// by N = 0; sw_estimate_cfo forwarded any length.
static void test_cfo_short_inputs(void) {
    float one = 0.5f;
    float* y = (float*)malloc(10 * sizeof(float));
    CHECK(y);
    for (int i = 0; i < 10; i++) y[i] = (float)i;
    CHECK(sync_schmidl_cox_cfo(y, 10, 8, 44100.0f) == 0.0f); // len < 2N
    CHECK(sync_schmidl_cox_cfo(y, 10, 0, 44100.0f) == 0.0f); // N = 0
    CHECK(sync_schmidl_cox_cfo(y, 10, 4, NAN) == 0.0f);      // bad fs
    free(y);

    float cfo = 1.0f;
    sw_config_t cfg = default_cfg(1);
    CHECK(sw_estimate_cfo(&one, 1, cfg, &cfo) == SW_ERR_SYNC);
    printf("PASS: CFO estimation bounds-checks short inputs\n");
}

// Every config-taking entry point now validates sw_config_t first.
static void test_config_validation(void) {
    sw_config_t zero;
    memset(&zero, 0, sizeof zero);
    CHECK(sw_config_validate(zero) == SW_OK); // all defaults
    sw_config_t css_ok = default_cfg(0), ofdm_ok = default_cfg(1);
    CHECK(sw_config_validate(css_ok) == SW_OK);
    CHECK(sw_config_validate(ofdm_ok) == SW_OK);

    sw_config_t c = default_cfg(0);
    c.symbol_duration = NAN;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(0); c.symbol_duration = INFINITY;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(0); c.sample_rate = -44100;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(0); c.sf = 30;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(1); c.num_subcarriers = 100; // not a power of two
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(1); c.num_subcarriers = 1 << 30;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(1); c.cp_length = 1000;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(0); c.modulation = 7;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);
    c = default_cfg(0); c.carrier_freq = 30000.0f; // above Nyquist at 44.1 kHz
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);

    // Entry points reject instead of allocating from garbage.
    float s[64] = {0};
    uint8_t bits[8] = {0xFF};
    size_t len = 64;
    c = default_cfg(0); c.symbol_duration = INFINITY;
    CHECK(sw_css_modulate(bits, 8, c, s, &len) == SW_ERR_BAD_PARAM);
    CHECK(sw_css_demodulate(s, 64, c, bits, &len) == SW_ERR_BAD_PARAM);
    c = default_cfg(1); c.num_subcarriers = -256;
    CHECK(sw_ofdm_demodulate(s, 64, c, bits, &len) == SW_ERR_BAD_PARAM);
    void* handle = NULL;
    c = default_cfg(0); c.sample_rate = -1; // used to size the ring buffer
    CHECK(sw_audio_capture_start(c, &handle) == SW_ERR_BAD_PARAM && handle == NULL);
    CHECK(sw_audio_playback_start(c, &handle) == SW_ERR_BAD_PARAM && handle == NULL);
    printf("PASS: sw_config_validate guards every entry point\n");
}

// css_modulate recomputed the symbol length in float precision; when it
// rounded one sample above the chirp template every bit over-read the
// template. Check lengths and a clean round trip across many timings.
static void test_css_symbol_length_consistency(void) {
    const int rates[] = {8000, 22050, 44100, 48000};
    const float durs[] = {0.005f, 0.0113f, 0.0127f, 0.02f, 0.0333f};
    const uint8_t payload[2] = {0xC3, 0x5A};
    for (size_t r = 0; r < sizeof rates / sizeof *rates; r++) {
        for (size_t d = 0; d < sizeof durs / sizeof *durs; d++) {
            sw_config_t c = default_cfg(0);
            c.sample_rate = rates[r];
            c.symbol_duration = durs[d];
            c.carrier_freq = 0.3f * (float)rates[r];
            c.bandwidth = 0.05f * (float)rates[r];
            size_t cap = 0;
            float dummy;
            int rc = sw_css_modulate(payload, 16, c, &dummy, &cap);
            CHECK(rc == SW_ERR_OVERFLOW && cap > 0);
            CHECK(cap % (10 + 16) == 0); // 10 preamble chirps + 16 symbols
            float* s = (float*)malloc(cap * sizeof(float));
            CHECK(s);
            size_t len = cap;
            CHECK(sw_css_modulate(payload, 16, c, s, &len) == SW_OK && len == cap);
            uint8_t out[8] = {0};
            size_t bit_len = 64;
            CHECK(sw_css_demodulate(s, len, c, out, &bit_len) == SW_OK);
            CHECK(bit_len >= 16 && out[0] == payload[0] && out[1] == payload[1]);
            free(s);
        }
    }
    printf("PASS: CSS symbol length matches template; clean round trips decode\n");
}

// ofdm_demodulate read two preamble symbols past frame_start and computed
// (payload_len - 2*sym) with unsigned wrap-around on short inputs.
static void test_ofdm_short_input(void) {
    sw_config_t c = default_cfg(1);
    size_t n = 300; // < 3 * (256 + 32)
    float* s = (float*)calloc(n, sizeof(float));
    CHECK(s);
    for (size_t i = 0; i < n; i++) s[i] = (i % 2) ? 0.5f : -0.5f;
    uint8_t out[64];
    size_t bit_len = sizeof out * 8;
    int rc = sw_ofdm_demodulate(s, n, c, out, &bit_len);
    CHECK(rc != SW_OK);
    free(s);
    printf("PASS: OFDM demodulator rejects inputs shorter than a frame\n");
}

int main(void) {
    test_rs_k31_uses_32_parity();
    test_rs_decode_rejects_hostile_lengths();
    test_packet_limits();
    test_fec_round_trip();
    test_cfo_short_inputs();
    test_config_validation();
    test_css_symbol_length_consistency();
    test_ofdm_short_input();
    printf("All memory-safety regression tests passed.\n");
    return 0;
}
