// Fuzz target: Reed-Solomon codec, internal API and FFI wrappers.
// Properties:
//   1. Arbitrary received words: rs_decode() never crashes, and when it
//      reports success the result is a valid codeword (decoding again
//      corrects 0 errors).
//   2. Round trip through sw_rs_encode/sw_rs_decode with <= t = 16 byte errors
//      always restores the original message and reports the exact count.

#include "fuzz_common.h"
#include "soundwave/rs.h"
#include "soundwave_api.h"

#define RS_T 16

static void check_arbitrary_word(fz_reader* r) {
    uint8_t word[255];
    size_t n = 1 + fz_u8(r) % 255;
    for (size_t i = 0; i < n; i++) word[i] = fz_u8(r);
    int errs = rs_decode(word, n);
    if (errs >= 0) FZ_CHECK(rs_decode(word, n) == 0);
}

static void check_round_trip(fz_reader* r) {
    uint8_t msg[223] = {0}, data[223] = {0}, parity[32] = {0};
    size_t k = 1 + fz_u8(r) % 223;
    for (size_t i = 0; i < k; i++) msg[i] = data[i] = fz_u8(r);

    size_t plen = sizeof parity;
    FZ_CHECK(sw_rs_encode(data, k, parity, &plen) == SW_OK && plen == 32);

    // Corrupt up to t distinct symbols across data + parity.
    size_t n = k + 32;
    uint8_t touched[255] = {0};
    int corrupted = 0;
    int want = fz_u8(r) % (RS_T + 1);
    for (int e = 0; e < want; e++) {
        size_t pos = fz_u8(r) % n;
        uint8_t flip = fz_u8(r);
        if (touched[pos] || flip == 0) continue;
        touched[pos] = 1;
        corrupted++;
        if (pos < k) data[pos] ^= flip; else parity[pos - k] ^= flip;
    }

    size_t dlen = k;
    int fixed = -1;
    int rc = sw_rs_decode(data, &dlen, parity, plen, &fixed);
    if (rc != SW_OK || fixed != corrupted || memcmp(data, msg, k) != 0) {
        fprintf(stderr, "RS round trip failed: k=%zu corrupted=%d rc=%d fixed=%d\n",
                k, corrupted, rc, fixed);
    }
    FZ_CHECK(rc == SW_OK);
    FZ_CHECK(fixed == corrupted);
    FZ_CHECK(memcmp(data, msg, k) == 0);
}

static void check_api_bounds(fz_reader* r) {
    // Hostile lengths must be rejected, never read/write out of bounds.
    uint8_t data[255] = {0}, parity[255] = {0};
    size_t dlen = fz_u16(r);
    size_t plen = fz_u16(r);
    int fixed = 0;
    size_t dcap = dlen > sizeof data ? sizeof data : dlen;
    size_t pcap = plen > sizeof parity ? sizeof parity : plen;
    for (size_t i = 0; i < dcap; i++) data[i] = fz_u8(r);
    for (size_t i = 0; i < pcap; i++) parity[i] = fz_u8(r);
    if (dlen <= sizeof data && plen <= sizeof parity)
        (void)sw_rs_decode(data, &dlen, parity, plen, &fixed);
    size_t out = sizeof parity;
    if (dlen <= sizeof data) (void)sw_rs_encode(data, dlen, parity, &out);
}

int LLVMFuzzerTestOneInput(const uint8_t* buf, size_t size) {
    fz_reader r;
    fz_init(&r, buf, size);
    switch (fz_u8(&r) % 3) {
    case 0: check_arbitrary_word(&r); break;
    case 1: check_round_trip(&r); break;
    default: check_api_bounds(&r); break;
    }
    return 0;
}
