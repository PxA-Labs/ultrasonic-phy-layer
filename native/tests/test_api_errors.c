// Error-path tests for the public C API (the FFI trust boundary): config
// validation, buffer-size negotiation (SW_ERR_OVERFLOW reports the required
// size), argument checks and AGC handle validation (issue #36).

#include "soundwave_api.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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

static sw_config_t cfg_for(int modulation) {
    sw_config_t c;
    memset(&c, 0, sizeof c);
    c.sample_rate = 44100;
    c.modulation = modulation;
    c.sf = 8;
    c.num_subcarriers = 256;
    c.cp_length = 64;
    c.num_pilots = 8;
    c.carrier_freq = 19000.0f;
    c.bandwidth = 2000.0f;
    c.symbol_duration = 0.02f;
    c.amplitude = 0.8f;
    c.threshold = 3.0f;
    c.ofdm_modulation = 1;
    c.coding_rate = 0.5f;
    return c;
}

/* ------------------------------------------------------------------------ */

static void test_config_validation_table(void) {
    const sw_config_t ok = cfg_for(1);
    CHECK(sw_config_validate(ok) == SW_OK);
    CHECK(sw_config_validate(cfg_for(0)) == SW_OK);
    sw_config_t zero;
    memset(&zero, 0, sizeof zero);
    CHECK(sw_config_validate(zero) == SW_OK); // all-defaults config is valid

    // Boundary values that must be accepted.
    sw_config_t c = ok;
    c.sample_rate = 8000; c.carrier_freq = 4000.0f; c.bandwidth = 4000.0f;
    CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.sample_rate = 192000;                CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.sf = 6;                              CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.sf = 12;                             CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.num_subcarriers = 16; c.cp_length = 16; c.num_pilots = 8;
    CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.num_subcarriers = 4096;              CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.amplitude = 1.0f;                    CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.symbol_duration = 1.0f;              CHECK(sw_config_validate(c) == SW_OK);
    c = ok; c.cp_length = 256; c.num_pilots = 128; CHECK(sw_config_validate(c) == SW_OK);
    // sample_rate 0 means the 44.1 kHz default: Nyquist is 22050 Hz.
    c = ok; c.sample_rate = 0; c.carrier_freq = 22050.0f;
    CHECK(sw_config_validate(c) == SW_OK);
    c.carrier_freq = 22100.0f;
    CHECK(sw_config_validate(c) == SW_ERR_BAD_PARAM);

    // Every rejection rule.
#define REJECT(field, value)                                                   \
    do {                                                                       \
        sw_config_t b = ok;                                                    \
        b.field = value;                                                       \
        if (sw_config_validate(b) != SW_ERR_BAD_PARAM) {                       \
            fprintf(stderr, "accepted %s = %s\n", #field, #value);             \
            exit(1);                                                           \
        }                                                                      \
    } while (0)
    REJECT(modulation, 2);
    REJECT(modulation, -1);
    REJECT(equalizer, 2);
    REJECT(ofdm_modulation, 2);
    REJECT(sample_rate, 7999);
    REJECT(sample_rate, 192001);
    REJECT(sample_rate, -44100);
    REJECT(coding_rate, NAN);
    REJECT(coding_rate, INFINITY);
    REJECT(threshold, -1.0f);
    REJECT(threshold, NAN);
    REJECT(carrier_freq, 22051.0f);
    REJECT(carrier_freq, -1.0f);
    REJECT(bandwidth, 30000.0f);
    REJECT(bandwidth, INFINITY);
    REJECT(symbol_duration, 1.5f);
    REJECT(symbol_duration, NAN);
    REJECT(amplitude, 1.01f);
    REJECT(amplitude, -0.1f);
    REJECT(sf, 5);
    REJECT(sf, 13);
    REJECT(num_subcarriers, 100);  // not a power of two
    REJECT(num_subcarriers, 8);    // too small
    REJECT(num_subcarriers, 8192); // too large
    REJECT(num_subcarriers, -256);
    REJECT(cp_length, -1);
    REJECT(cp_length, 257);
    REJECT(num_pilots, -1);
    REJECT(num_pilots, 129);
#undef REJECT
    printf("PASS: sw_config_validate accepts boundaries and rejects each bad field\n");
}

static void test_crc_and_rs_arguments(void) {
    uint32_t crc = 0xDEADBEEF;
    CHECK(sw_crc32((const uint8_t*)"", 0, &crc) == SW_OK && crc == 0);

    uint8_t data[224] = {0}, parity[32];
    size_t plen = 0;
    CHECK(sw_rs_encode(data, 0, parity, &plen) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_encode(data, 224, parity, &plen) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_encode(NULL, 10, parity, &plen) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_encode(data, 10, NULL, &plen) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_encode(data, 10, parity, NULL) == SW_ERR_BAD_PARAM);

    // Shortest code: 1 data byte + 32 parity, with 16 errors in the parity.
    data[0] = 0x42;
    CHECK(sw_rs_encode(data, 1, parity, &plen) == SW_OK && plen == 32);
    for (int i = 0; i < 16; i++) parity[i * 2] ^= 0x81;
    size_t dlen = 1;
    int fixed = -1;
    CHECK(sw_rs_decode(data, &dlen, parity, 32, &fixed) == SW_OK);
    CHECK(fixed == 16 && data[0] == 0x42 && dlen == 1);

    dlen = 0;
    CHECK(sw_rs_decode(data, &dlen, parity, 32, &fixed) == SW_ERR_BAD_PARAM);
    dlen = 1;
    CHECK(sw_rs_decode(data, &dlen, parity, 1, &fixed) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_decode(data, &dlen, parity, 255, &fixed) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_decode(data, &dlen, NULL, 32, &fixed) == SW_ERR_BAD_PARAM);
    CHECK(sw_rs_decode(data, &dlen, parity, 32, NULL) == SW_ERR_BAD_PARAM);
    printf("PASS: CRC/RS API argument checks and shortest RS code\n");
}

/* ------------------------------------------------------------------------ */

typedef int (*mod_fn)(const uint8_t*, size_t, sw_config_t, float*, size_t*);

// Size negotiation: too small a buffer returns SW_ERR_OVERFLOW plus the
// required size; retrying with that size succeeds with identical length.
static float* negotiate_modulate(mod_fn fn, const uint8_t* bits, size_t nbits,
                                 sw_config_t cfg, size_t* out_len) {
    float probe[8];
    size_t need = 8;
    CHECK(fn(bits, nbits, cfg, probe, &need) == SW_ERR_OVERFLOW);
    CHECK(need > 8);
    float* buf = (float*)malloc(need * sizeof(float));
    CHECK(buf != NULL);
    size_t len = need;
    CHECK(fn(bits, nbits, cfg, buf, &len) == SW_OK);
    CHECK(len == need);
    *out_len = len;
    return buf;
}

static void check_modulate_arguments(mod_fn fn, sw_config_t cfg) {
    uint8_t bits[4] = {1, 2, 3, 4};
    float out[16];
    size_t len = 16;
    CHECK(fn(NULL, 32, cfg, out, &len) == SW_ERR_BAD_PARAM);
    CHECK(fn(bits, 0, cfg, out, &len) == SW_ERR_BAD_PARAM);
    CHECK(fn(bits, 32, cfg, NULL, &len) == SW_ERR_BAD_PARAM);
    CHECK(fn(bits, 32, cfg, out, NULL) == SW_ERR_BAD_PARAM);
    sw_config_t bad = cfg;
    bad.amplitude = 2.0f;
    CHECK(fn(bits, 32, bad, out, &len) == SW_ERR_BAD_PARAM);
}

static void test_css_buffer_negotiation(void) {
    sw_config_t cfg = cfg_for(0);
    check_modulate_arguments(sw_css_modulate, cfg);

    const uint8_t msg[6] = {'S', 'o', 'u', 'n', 'd', '!'};
    size_t n = 0;
    float* s = negotiate_modulate(sw_css_modulate, msg, 48, cfg, &n);

    uint8_t out[64];
    size_t bits = 8; // room for one byte only
    CHECK(sw_css_demodulate(s, n, cfg, out, &bits) == SW_ERR_OVERFLOW);
    CHECK(bits == 48); // required size reported
    bits = sizeof out * 8;
    CHECK(sw_css_demodulate(s, n, cfg, out, &bits) == SW_OK);
    CHECK(bits == 48 && memcmp(out, msg, 6) == 0);

    // Argument checks.
    bits = 64;
    CHECK(sw_css_demodulate(NULL, n, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    CHECK(sw_css_demodulate(s, 0, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    CHECK(sw_css_demodulate(s, n, cfg, NULL, &bits) == SW_ERR_BAD_PARAM);
    CHECK(sw_css_demodulate(s, n, cfg, out, NULL) == SW_ERR_BAD_PARAM);
    bits = 0;
    CHECK(sw_css_demodulate(s, n, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    bits = 64;
    sw_config_t bad = cfg;
    bad.sf = 99;
    CHECK(sw_css_demodulate(s, n, bad, out, &bits) == SW_ERR_BAD_PARAM);
    free(s);
    printf("PASS: CSS modulate/demodulate report required buffer sizes\n");
}

static void test_ofdm_buffer_negotiation(void) {
    sw_config_t cfg = cfg_for(1);
    check_modulate_arguments(sw_ofdm_modulate, cfg);

    uint8_t msg[24];
    for (int i = 0; i < 24; i++) msg[i] = (uint8_t)(i * 37 + 5);
    size_t n = 0;
    float* s = negotiate_modulate(sw_ofdm_modulate, msg, 24 * 8, cfg, &n);

    uint8_t out[4096];
    size_t bits = 8;
    CHECK(sw_ofdm_demodulate(s, n, cfg, out, &bits) == SW_ERR_OVERFLOW);
    size_t need = bits;
    CHECK(need >= 24 * 8);
    CHECK(need <= sizeof out * 8);
    bits = need;
    CHECK(sw_ofdm_demodulate(s, n, cfg, out, &bits) == SW_OK);
    CHECK(bits == need);
    CHECK(memcmp(out, msg, 24) == 0); // clean channel: exact payload

    bits = 64;
    CHECK(sw_ofdm_demodulate(NULL, n, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_demodulate(s, 0, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_demodulate(s, n, cfg, NULL, &bits) == SW_ERR_BAD_PARAM);
    bits = 0;
    CHECK(sw_ofdm_demodulate(s, n, cfg, out, &bits) == SW_ERR_BAD_PARAM);
    bits = 64;
    sw_config_t bad = cfg;
    bad.num_subcarriers = 300;
    CHECK(sw_ofdm_demodulate(s, n, bad, out, &bits) == SW_ERR_BAD_PARAM);

    // A truncated frame fails cleanly and reports no output.
    bits = sizeof out * 8;
    CHECK(sw_ofdm_demodulate(s, 100, cfg, out, &bits) != SW_OK);
    CHECK(bits == 0);

    // Equalized constellation points: argument checks and capacity bound.
    float iq[2 * 4096];
    size_t pts = 0;
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq, &pts) == SW_ERR_BAD_PARAM);
    pts = 4096;
    CHECK(sw_ofdm_equalized_symbols(NULL, n, cfg, iq, &pts) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, NULL, &pts) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq, NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg_for(0), iq, &pts) == SW_ERR_BAD_PARAM);
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq, &pts) == SW_OK);
    size_t all = pts;
    CHECK(all > 0 && all <= 4096);
    pts = 5;
    for (int i = 0; i < 2 * 4096; i++) iq[i] = 1234.0f;
    CHECK(sw_ofdm_equalized_symbols(s, n, cfg, iq, &pts) == SW_OK);
    CHECK(pts <= 5 && pts > 0);
    CHECK(iq[2 * 5] == 1234.0f); // nothing written past the capacity
    for (size_t i = 0; i < 2 * pts; i++) CHECK(isfinite(iq[i]));
    pts = 4096;
    CHECK(sw_ofdm_equalized_symbols(s, 100, cfg, iq, &pts) != SW_OK);
    CHECK(pts == 0);
    free(s);
    printf("PASS: OFDM modulate/demodulate/constellation buffer negotiation\n");
}

static void test_sync_arguments(void) {
    sw_config_t cfg = cfg_for(1);
    size_t start = 0;
    float snr = 0.0f, cfo = 0.0f;
    float* silence = (float*)calloc(20000, sizeof(float));
    CHECK(silence != NULL);

    CHECK(sw_detect_frame(silence, 0, cfg, &start, &snr) == SW_ERR_BAD_PARAM);
    CHECK(sw_detect_frame(silence, 20000, cfg, NULL, &snr) == SW_ERR_BAD_PARAM);
    CHECK(sw_detect_frame(silence, 20000, cfg, &start, NULL) == SW_ERR_BAD_PARAM);
    sw_config_t bad = cfg;
    bad.threshold = -3.0f;
    CHECK(sw_detect_frame(silence, 20000, bad, &start, &snr) == SW_ERR_BAD_PARAM);
    // Silence is not a frame, in either mode.
    CHECK(sw_detect_frame(silence, 20000, cfg, &start, &snr) == SW_ERR_SYNC);
    CHECK(sw_detect_frame(silence, 20000, cfg_for(0), &start, &snr) == SW_ERR_SYNC);

    // CFO needs two repeated (N + cp) periods.
    CHECK(sw_estimate_cfo(silence, 2 * (256 + 64) - 1, cfg, &cfo) == SW_ERR_SYNC);
    CHECK(sw_estimate_cfo(silence, 2 * (256 + 64), cfg, &cfo) == SW_OK);
    CHECK(isfinite(cfo));
    CHECK(sw_estimate_cfo(silence, 0, cfg, &cfo) == SW_ERR_BAD_PARAM);
    CHECK(sw_estimate_cfo(silence, 20000, cfg, NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_estimate_cfo(silence, 20000, bad, &cfo) == SW_ERR_BAD_PARAM);
    free(silence);
    printf("PASS: sync/CFO argument checks; silence is not detected as a frame\n");
}

static void test_audio_arguments(void) {
    // Only the validation paths: CI runners have no sound devices.
    void* h = (void*)0x1;
    sw_config_t bad = cfg_for(0);
    bad.sample_rate = 1000;
    CHECK(sw_audio_capture_start(cfg_for(0), NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_audio_capture_start(bad, &h) == SW_ERR_BAD_PARAM);
    CHECK(h == (void*)0x1); // untouched on failure
    CHECK(sw_audio_playback_start(cfg_for(0), NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_audio_playback_start(bad, &h) == SW_ERR_BAD_PARAM);
    CHECK(sw_audio_capture_stop(NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_audio_playback_stop(NULL) == SW_ERR_BAD_PARAM);
    float buf[4] = {0};
    size_t got = 0;
    CHECK(sw_audio_capture_read(NULL, buf, 4, &got) == SW_ERR_BAD_PARAM);
    CHECK(sw_audio_playback_write(NULL, buf, 4) == SW_ERR_BAD_PARAM);
    printf("PASS: audio API rejects NULL handles and invalid configs\n");
}

static void test_agc_handles(void) {
    void* h = (void*)0x1;
    CHECK(sw_agc_create(44100, 0.1f, NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(7999, 0.1f, &h) == SW_ERR_BAD_PARAM && h == NULL);
    CHECK(sw_agc_create(192001, 0.1f, &h) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(44100, -0.1f, &h) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(44100, 1.5f, &h) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_create(44100, NAN, &h) == SW_ERR_BAD_PARAM);

    // target 0 selects the default target.
    CHECK(sw_agc_create(48000, 0.0f, &h) == SW_OK && h != NULL);
    float x[256];
    for (int i = 0; i < 256; i++) x[i] = 0.01f * sinf(0.3f * (float)i);
    CHECK(sw_agc_process(h, x, 256) == SW_OK);
    CHECK(sw_agc_process(h, NULL, 0) == SW_OK);
    CHECK(sw_agc_process(h, NULL, 16) == SW_ERR_BAD_PARAM);
    float g = NAN;
    CHECK(sw_agc_get_gain_db(h, &g) == SW_OK && isfinite(g));
    CHECK(sw_agc_get_gain_db(h, NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_reset(h) == SW_OK);

    // A pointer that is not an AGC handle is rejected, never dereferenced as
    // AGC state (the magic tag does not match).
    struct { uint32_t magic; void* agc; } fake = {0x12345678u, &fake};
    CHECK(sw_agc_process(&fake, x, 256) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_get_gain_db(&fake, &g) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_reset(&fake) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_destroy(&fake) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_process(NULL, x, 256) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_reset(NULL) == SW_ERR_BAD_PARAM);
    CHECK(sw_agc_destroy(NULL) == SW_ERR_BAD_PARAM);

    CHECK(sw_agc_destroy(h) == SW_OK);
    printf("PASS: AGC handle validation\n");
}

int main(void) {
    test_config_validation_table();
    test_crc_and_rs_arguments();
    test_css_buffer_negotiation();
    test_ofdm_buffer_negotiation();
    test_sync_arguments();
    test_audio_arguments();
    test_agc_handles();
    printf("All API error-path tests passed.\n");
    return 0;
}
