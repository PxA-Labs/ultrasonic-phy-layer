// Fuzz target: packet framing.
// Properties:
//   * packet_decode() on arbitrary frames never reads/writes out of bounds;
//   * packet_encode() -> packet_decode() round-trips every payload the encoder
//     accepts.

#include "fuzz_common.h"
#include "soundwave/packet.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    fz_reader r;
    fz_init(&r, data, size);
    packet_config_t cfg;
    packet_init(&cfg);

    uint8_t mode = fz_u8(&r);
    if (mode & 1) {
        // Hostile configuration values must be rejected, not trusted.
        cfg.preamble_len = (int)(int8_t)fz_u8(&r);
        cfg.header_len = (int)(int8_t)fz_u8(&r);
        cfg.max_payload = fz_u16(&r);
    }

    if (mode & 2) {
        // Decode arbitrary bytes into an exact-size payload buffer.
        size_t cap = fz_u8(&r);
        size_t flen = fz_remaining(&r);
        uint8_t* frame = (uint8_t*)malloc(flen ? flen : 1);
        uint8_t* payload = (uint8_t*)malloc(cap ? cap : 1);
        if (frame && payload) {
            memcpy(frame, r.data + r.pos, flen);
            size_t plen = 0;
            if (packet_decode(&cfg, frame, flen, payload, cap, &plen) == 0)
                FZ_CHECK(plen <= cap);
        }
        free(frame);
        free(payload);
        return 0;
    }

    // Round trip.
    size_t plen = fz_remaining(&r);
    if (plen > 512) plen = 512;
    const uint8_t* payload = r.data + r.pos;
    size_t cap = plen + 1024;
    uint8_t* frame = (uint8_t*)malloc(cap);
    uint8_t* out = (uint8_t*)malloc(plen ? plen : 1);
    if (frame && out) {
        size_t flen = 0, olen = 0;
        if (packet_encode(&cfg, payload, plen, frame, cap, &flen) == 0) {
            FZ_CHECK(flen <= cap);
            FZ_CHECK(packet_decode(&cfg, frame, flen, out, plen, &olen) == 0);
            FZ_CHECK(olen == plen);
            FZ_CHECK(plen == 0 || memcmp(out, payload, plen) == 0);
        }
    }
    free(frame);
    free(out);
    return 0;
}
