// Fuzz target: FEC (RS(255,223) + interleaving).
// Properties:
//   * fec_decode() on arbitrary input never crashes or reads uninitialised data;
//   * fec_encode() -> fec_decode() restores the data exactly, also after up to
//     16 corrupted bytes in the coded block.

#include "fuzz_common.h"
#include "soundwave/fec.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    fz_reader r;
    fz_init(&r, data, size);

    if (fz_u8(&r) & 1) {
        size_t clen = fz_remaining(&r);
        uint8_t* coded = (uint8_t*)malloc(clen ? clen : 1);
        if (!coded) return 0;
        memcpy(coded, r.data + r.pos, clen);
        uint8_t out[223];
        size_t olen = 0;
        int fixed = 0;
        (void)fec_decode(coded, clen, out, &olen, &fixed);
        free(coded);
        return 0;
    }

    uint8_t msg[223] = {0};
    size_t k = fz_u8(&r) % 224; // 0..223
    for (size_t i = 0; i < k; i++) msg[i] = fz_u8(&r);

    uint8_t coded[255];
    size_t clen = 0;
    FZ_CHECK(fec_encode(msg, k, coded, &clen) == 0);
    FZ_CHECK(clen == 255);

    uint8_t touched[255] = {0};
    int want = fz_u8(&r) % 17;
    for (int e = 0; e < want; e++) {
        size_t pos = fz_u8(&r) % 255;
        uint8_t flip = fz_u8(&r);
        if (touched[pos] || flip == 0) continue;
        touched[pos] = 1;
        coded[pos] ^= flip;
    }

    uint8_t out[223];
    size_t olen = 0;
    int fixed = 0;
    int rc = fec_decode(coded, clen, out, &olen, &fixed);
    if (rc < 0 || (k && memcmp(out, msg, k) != 0))
        fprintf(stderr, "FEC round trip failed: k=%zu rc=%d\n", k, rc);
    FZ_CHECK(rc >= 0);
    FZ_CHECK(olen >= k);
    FZ_CHECK(k == 0 || memcmp(out, msg, k) == 0);
    return 0;
}
