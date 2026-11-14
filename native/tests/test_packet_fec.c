// Unit tests for packet framing (packet.c) and the RS(255,223) FEC wrapper
// with block interleaving (fec.c): wire format, every rejection path, and
// error-correction limits (issue #36 coverage work).

#include "soundwave/crc.h"
#include "soundwave/fec.h"
#include "soundwave/packet.h"
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

#define FRAME_CAP 4096

static void fill(uint8_t* buf, size_t len, uint32_t seed) {
    for (size_t i = 0; i < len; i++) {
        seed = seed * 1664525u + 1013904223u;
        buf[i] = (uint8_t)(seed >> 24);
    }
}

/* ------------------------------------------------------------------------ */
/* Packet framing                                                           */
/* ------------------------------------------------------------------------ */

static void test_packet_defaults(void) {
    packet_config_t cfg;
    memset(&cfg, 0xFF, sizeof cfg);
    packet_init(&cfg);
    CHECK(cfg.sync_word == 0xA53C);
    CHECK(cfg.max_payload == 255);
    CHECK(cfg.preamble_len == 64);
    CHECK(cfg.header_len == 8);
    packet_init(NULL); // must not crash
    printf("PASS: packet_init defaults\n");
}

static void test_packet_wire_format(void) {
    packet_config_t cfg;
    packet_init(&cfg);
    const uint8_t payload[5] = {'h', 'e', 'l', 'l', 'o'};
    uint8_t frame[FRAME_CAP];
    memset(frame, 0xEE, sizeof frame);
    size_t flen = 0;
    CHECK(packet_encode(&cfg, payload, 5, frame, sizeof frame, &flen) == 0);
    // preamble + sync + header + payload + crc
    CHECK(flen == 64 + 2 + 8 + 5 + 4);
    for (int i = 0; i < 64; i++) CHECK(frame[i] == 0);
    CHECK(frame[64] == 0xA5 && frame[65] == 0x3C);
    CHECK(frame[66] == 5);   // length
    CHECK(frame[67] == 0);   // flags
    for (int i = 68; i < 74; i++) CHECK(frame[i] == 0); // reserved
    CHECK(memcmp(frame + 74, payload, 5) == 0);
    // CRC-32 over header + payload, big-endian.
    uint32_t crc = crc32_compute(frame + 66, 8 + 5);
    CHECK(frame[79] == (uint8_t)(crc >> 24));
    CHECK(frame[80] == (uint8_t)(crc >> 16));
    CHECK(frame[81] == (uint8_t)(crc >> 8));
    CHECK(frame[82] == (uint8_t)crc);
    CHECK(frame[83] == 0xEE); // nothing written past the frame
    printf("PASS: packet wire format (preamble, sync, header, payload, CRC)\n");
}

static void test_packet_round_trips(void) {
    const size_t sizes[] = {0, 1, 2, 100, 254, 255};
    const struct { uint16_t sync; int pre; int hdr; } cfgs[] = {
        {0xA53C, 64, 8}, {0x1234, 0, 2}, {0xFFFF, 4096, 256}, {0x0000, 7, 3},
    };
    static uint8_t frame[4096 + 2 + 256 + 255 + 4];
    for (size_t c = 0; c < sizeof cfgs / sizeof cfgs[0]; c++) {
        packet_config_t cfg;
        packet_init(&cfg);
        cfg.sync_word = cfgs[c].sync;
        cfg.preamble_len = cfgs[c].pre;
        cfg.header_len = cfgs[c].hdr;
        for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
            uint8_t payload[255], out[255];
            fill(payload, sizes[s], (uint32_t)(c * 31 + s));
            size_t flen = 0, olen = 999;
            CHECK(packet_encode(&cfg, sizes[s] ? payload : NULL, sizes[s], frame,
                                sizeof frame, &flen) == 0);
            CHECK(flen == (size_t)cfgs[c].pre + 2 + (size_t)cfgs[c].hdr + sizes[s] + 4);
            CHECK(packet_decode(&cfg, frame, flen, out, sizeof out, &olen) == 0);
            CHECK(olen == sizes[s]);
            CHECK(memcmp(out, payload, sizes[s]) == 0);
            // Trailing bytes after the frame are ignored.
            CHECK(packet_decode(&cfg, frame, sizeof frame, out, sizeof out, &olen) == 0);
            CHECK(olen == sizes[s]);
        }
    }
    printf("PASS: packet round trips across payload sizes and configs\n");
}

static void test_packet_encode_rejects(void) {
    packet_config_t cfg;
    packet_init(&cfg);
    uint8_t payload[256] = {0}, frame[FRAME_CAP];
    size_t flen = 0;

    CHECK(packet_encode(NULL, payload, 4, frame, sizeof frame, &flen) == -1);
    CHECK(packet_encode(&cfg, payload, 4, NULL, sizeof frame, &flen) == -1);
    CHECK(packet_encode(&cfg, payload, 4, frame, sizeof frame, NULL) == -1);
    CHECK(packet_encode(&cfg, NULL, 4, frame, sizeof frame, &flen) == -1);
    CHECK(packet_encode(&cfg, payload, 256, frame, sizeof frame, &flen) == -1);

    // Exactly-sized buffer works, one byte less is rejected without writing.
    size_t need = 64 + 2 + 8 + 10 + 4;
    CHECK(packet_encode(&cfg, payload, 10, frame, need, &flen) == 0 && flen == need);
    flen = 12345;
    CHECK(packet_encode(&cfg, payload, 10, frame, need - 1, &flen) == -1);
    CHECK(flen == 12345);

    // A smaller configured max_payload is enforced.
    packet_config_t small = cfg;
    small.max_payload = 10;
    CHECK(packet_encode(&small, payload, 10, frame, sizeof frame, &flen) == 0);
    CHECK(packet_encode(&small, payload, 11, frame, sizeof frame, &flen) == -1);

    // Invalid configurations.
    const struct { int pre; int hdr; size_t maxp; } bad[] = {
        {-1, 8, 255}, {4097, 8, 255}, {64, 1, 255}, {64, 257, 255}, {64, 8, 256},
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        packet_config_t b = cfg;
        b.preamble_len = bad[i].pre;
        b.header_len = bad[i].hdr;
        b.max_payload = bad[i].maxp;
        CHECK(packet_encode(&b, payload, 4, frame, sizeof frame, &flen) == -1);
    }
    printf("PASS: packet_encode rejects bad arguments, configs and short buffers\n");
}

static void test_packet_decode_rejects(void) {
    packet_config_t cfg;
    packet_init(&cfg);
    uint8_t payload[40], frame[FRAME_CAP], out[255];
    fill(payload, sizeof payload, 7);
    size_t flen = 0, olen = 0;
    CHECK(packet_encode(&cfg, payload, sizeof payload, frame, sizeof frame, &flen) == 0);

    // Argument checks.
    CHECK(packet_decode(NULL, frame, flen, out, sizeof out, &olen) == -1);
    CHECK(packet_decode(&cfg, NULL, flen, out, sizeof out, &olen) == -1);
    CHECK(packet_decode(&cfg, frame, flen, out, sizeof out, NULL) == -1);
    CHECK(packet_decode(&cfg, frame, flen, NULL, sizeof out, &olen) == -1);

    // Shorter than the smallest possible frame, and truncated mid-payload.
    CHECK(packet_decode(&cfg, frame, 64 + 2 + 8 + 3, out, sizeof out, &olen) == -1);
    CHECK(packet_decode(&cfg, frame, flen - 1, out, sizeof out, &olen) == -1);

    // Output buffer one byte too small.
    CHECK(packet_decode(&cfg, frame, flen, out, sizeof payload - 1, &olen) == -1);

    // Wrong sync word (either byte).
    uint8_t bad[FRAME_CAP];
    memcpy(bad, frame, flen);
    bad[64] ^= 0x01;
    CHECK(packet_decode(&cfg, bad, flen, out, sizeof out, &olen) == -1);
    memcpy(bad, frame, flen);
    bad[65] ^= 0x80;
    CHECK(packet_decode(&cfg, bad, flen, out, sizeof out, &olen) == -1);

    // Any single-bit error in header, payload or CRC is caught by CRC-32
    // (or by the length check when the length byte itself is hit).
    for (size_t pos = 66; pos < flen; pos++) {
        for (int bit = 0; bit < 8; bit++) {
            memcpy(bad, frame, flen);
            bad[pos] ^= (uint8_t)(1u << bit);
            olen = 777;
            CHECK(packet_decode(&cfg, bad, flen, out, sizeof out, &olen) == -1);
            CHECK(olen == 777); // no partial output reported
        }
    }

    // Preamble content is not checked (it is only for the modem's AGC/sync).
    memcpy(bad, frame, flen);
    bad[0] = 0x55;
    CHECK(packet_decode(&cfg, bad, flen, out, sizeof out, &olen) == 0);

    // A receiver with a smaller max_payload rejects a longer (valid) frame.
    packet_config_t small = cfg;
    small.max_payload = 39;
    CHECK(packet_decode(&small, frame, flen, out, sizeof out, &olen) == -1);

    // Hostile configs are rejected before touching the frame.
    packet_config_t hostile = cfg;
    hostile.header_len = 0;
    CHECK(packet_decode(&hostile, frame, flen, out, sizeof out, &olen) == -1);

    // Empty payload: decoding into a NULL/0-capacity buffer is allowed.
    CHECK(packet_encode(&cfg, NULL, 0, frame, sizeof frame, &flen) == 0);
    olen = 5;
    CHECK(packet_decode(&cfg, frame, flen, NULL, 0, &olen) == 0 && olen == 0);
    printf("PASS: packet_decode rejects corrupted, truncated and oversized frames\n");
}

/* ------------------------------------------------------------------------ */
/* Interleaver                                                              */
/* ------------------------------------------------------------------------ */

static void test_interleaver_is_permutation(void) {
    const size_t lens[] = {1, 16, 17, 18, 34, 100, 254, 255};
    for (size_t l = 0; l < sizeof lens / sizeof lens[0]; l++) {
        size_t n = lens[l];
        uint8_t in[255], mid[255], back[255];
        for (size_t i = 0; i < n; i++) in[i] = (uint8_t)i; // distinct values
        memset(mid, 0xEE, sizeof mid);
        fec_interleave(in, n, mid);
        // Every input symbol appears exactly once.
        int seen[256] = {0};
        for (size_t i = 0; i < n; i++) seen[mid[i]]++;
        for (size_t i = 0; i < n; i++) CHECK(seen[i] == 1);
        if (n < sizeof mid) CHECK(mid[n] == 0xEE);
        fec_deinterleave(mid, n, back);
        CHECK(memcmp(back, in, n) == 0);
    }
    printf("PASS: interleaver is a length-preserving permutation\n");
}

static void test_interleaver_spreads_bursts(void) {
    uint8_t in[255], out[255];
    for (int i = 0; i < 255; i++) in[i] = (uint8_t)i;
    fec_interleave(in, 255, out);
    // Column-major read-out with depth 17: neighbours on the channel were 17
    // apart in the codeword.
    for (int k = 0; k + 1 < 15; k++) CHECK(out[k + 1] - out[k] == 17);
    CHECK(out[0] == 0 && out[15] == 1);
    printf("PASS: interleaver spaces adjacent channel symbols 17 apart\n");
}

static void test_interleaver_ignores_bad_args(void) {
    uint8_t buf[34], out[34];
    for (int i = 0; i < 34; i++) buf[i] = (uint8_t)(i + 1);
    memset(out, 0xEE, sizeof out);
    fec_interleave(NULL, 34, out);
    fec_interleave(buf, 34, NULL);
    fec_deinterleave(NULL, 34, out);
    fec_deinterleave(buf, 34, NULL);
    for (int i = 0; i < 34; i++) CHECK(out[i] == 0xEE);
    // In-place (aliased) calls are refused rather than corrupting the data.
    fec_interleave(buf, 34, buf);
    fec_deinterleave(buf, 34, buf);
    for (int i = 0; i < 34; i++) CHECK(buf[i] == (uint8_t)(i + 1));
    printf("PASS: interleaver ignores NULL and aliased buffers\n");
}

/* ------------------------------------------------------------------------ */
/* FEC encode / decode                                                      */
/* ------------------------------------------------------------------------ */

static void test_fec_encode_rejects(void) {
    uint8_t data[224] = {0}, coded[255];
    size_t clen = 0;
    CHECK(fec_encode(data, 224, coded, &clen) == -1);
    CHECK(fec_encode(NULL, 5, coded, &clen) == -1);
    CHECK(fec_encode(data, 5, NULL, &clen) == -1);
    CHECK(fec_encode(data, 5, coded, NULL) == -1);
    // Empty message: all-zero codeword (RS of zeros has zero parity).
    CHECK(fec_encode(NULL, 0, coded, &clen) == 0 && clen == 255);
    for (int i = 0; i < 255; i++) CHECK(coded[i] == 0);
    printf("PASS: fec_encode argument checks and empty message\n");
}

static void test_fec_clean_and_padded(void) {
    uint8_t msg[223], coded[255], out[223];
    fill(msg, sizeof msg, 99);
    for (size_t k = 1; k <= 223; k += 37) {
        size_t clen = 0, olen = 0;
        int fixed = 99;
        CHECK(fec_encode(msg, k, coded, &clen) == 0 && clen == 255);
        CHECK(fec_decode(coded, clen, out, &olen, &fixed) == 0);
        CHECK(fixed == 0 && olen == 223);
        CHECK(memcmp(out, msg, k) == 0);
        for (size_t i = k; i < 223; i++) CHECK(out[i] == 0); // zero padding
    }
    printf("PASS: fec clean decode returns zero-padded 223-byte block\n");
}

static void test_fec_corrects_up_to_16_and_rejects_more(void) {
    uint8_t msg[223], coded[255], rx[255], out[223];
    fill(msg, sizeof msg, 2024);
    size_t clen = 0, olen = 0;
    int fixed = 0;
    CHECK(fec_encode(msg, sizeof msg, coded, &clen) == 0);

    // A 16-byte burst on the channel (the full correction capacity).
    memcpy(rx, coded, 255);
    for (int i = 100; i < 116; i++) rx[i] ^= 0xA5;
    CHECK(fec_decode(rx, 255, out, &olen, &fixed) == 16);
    CHECK(fixed == 16 && memcmp(out, msg, 223) == 0);

    // Scattered errors, including the last coded byte.
    memcpy(rx, coded, 255);
    const int pos[] = {0, 3, 50, 77, 128, 200, 254};
    for (size_t i = 0; i < sizeof pos / sizeof pos[0]; i++) rx[pos[i]] ^= (uint8_t)(i + 1);
    CHECK(fec_decode(rx, 255, out, &olen, NULL) == 7); // errors_corrected optional
    CHECK(memcmp(out, msg, 223) == 0);

    // 17+ symbol errors exceed t = 16: reported as a failure, not miscorrected.
    memcpy(rx, coded, 255);
    for (int i = 0; i < 40; i++) rx[i * 6] ^= 0x3C;
    fixed = 0;
    CHECK(fec_decode(rx, 255, out, &olen, &fixed) == -1);
    CHECK(fixed < 0);

    // Only the first 255 bytes form the block; extra bytes are ignored.
    uint8_t longer[300];
    memcpy(longer, coded, 255);
    memset(longer + 255, 0x77, 45);
    CHECK(fec_decode(longer, sizeof longer, out, &olen, &fixed) == 0);
    CHECK(memcmp(out, msg, 223) == 0);
    printf("PASS: fec corrects 16 symbol errors and rejects 40\n");
}

static void test_fec_decode_rejects(void) {
    uint8_t coded[255] = {0}, out[223];
    size_t olen = 0;
    int fixed = 5;
    CHECK(fec_decode(coded, 254, out, &olen, &fixed) == -1);
    CHECK(fixed == -1); // reset even on argument errors
    CHECK(fec_decode(NULL, 255, out, &olen, &fixed) == -1);
    CHECK(fec_decode(coded, 255, NULL, &olen, &fixed) == -1);
    CHECK(fec_decode(coded, 255, out, NULL, &fixed) == -1);
    CHECK(fec_decode(coded, 255, out, &olen, NULL) == 0); // all-zero block is valid
    printf("PASS: fec_decode argument checks\n");
}

int main(void) {
    test_packet_defaults();
    test_packet_wire_format();
    test_packet_round_trips();
    test_packet_encode_rejects();
    test_packet_decode_rejects();
    test_interleaver_is_permutation();
    test_interleaver_spreads_bursts();
    test_interleaver_ignores_bad_args();
    test_fec_encode_rejects();
    test_fec_clean_and_padded();
    test_fec_corrects_up_to_16_and_rejects_more();
    test_fec_decode_rejects();
    printf("All packet/FEC tests passed.\n");
    return 0;
}
