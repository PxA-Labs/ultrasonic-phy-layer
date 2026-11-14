// soundwave-cli frame format (native/tools/soundwave_cli/frame_format.c).
// The layout must be byte-identical to the app's FrameCodec
// (soundwave_app/lib/engine/frame_codec.dart): [CRC-32 LE][payload][RS 32 B].
// The same golden prefix is asserted on the Dart side in
// soundwave_app/test/native/cli_compat_test.dart.

#include "frame_format.h"
#include "soundwave_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                    \
        }                                                                  \
    } while (0)

static void test_golden_layout(void) {
    uint8_t f[SW_FRAME_MAX_LEN];
    size_t n = sw_frame_encode((const uint8_t*)"hello", 5, 1, f, sizeof f);
    CHECK(n == 4 + 5 + 32);
    // CRC-32("hello") = 0x3610A686, stored little-endian, then the payload.
    const uint8_t head[9] = {0x86, 0xA6, 0x10, 0x36, 'h', 'e', 'l', 'l', 'o'};
    CHECK(memcmp(f, head, sizeof head) == 0);
    // Parity is sw_rs_encode over CRC + payload.
    uint8_t parity[32];
    size_t plen = sizeof parity;
    CHECK(sw_rs_encode(f, 9, parity, &plen) == SW_OK && plen == 32);
    CHECK(memcmp(f + 9, parity, 32) == 0);

    size_t m = sw_frame_encode((const uint8_t*)"hello", 5, 0, f, sizeof f);
    CHECK(m == 9 && memcmp(f, head, sizeof head) == 0);
}

static void test_decode_with_trailing_bytes_and_errors(void) {
    uint8_t payload[SW_FRAME_MAX_PAYLOAD];
    for (size_t i = 0; i < sizeof payload; i++) payload[i] = (uint8_t)(i * 31 + 7);
    const size_t lens[] = {1, 2, 27, 100, SW_FRAME_MAX_PAYLOAD};
    for (size_t li = 0; li < sizeof lens / sizeof *lens; li++) {
        for (int rs = 0; rs <= 1; rs++) {
            size_t len = lens[li];
            uint8_t buf[SW_FRAME_MAX_LEN + 64];
            size_t n = sw_frame_encode(payload, len, rs, buf, sizeof buf);
            CHECK(n == 4 + len + (rs ? 32u : 0u));
            // Demodulator output continues with garbage after the frame.
            for (size_t i = n; i < sizeof buf; i++) buf[i] = (uint8_t)(0xA5 ^ i);
            if (rs) {
                for (int e = 0; e < 16; e++) buf[(e * 7) % n] ^= 0x5A; // t = 16
            }
            uint8_t work[SW_FRAME_MAX_LEN];
            size_t off = 0, plen = 0, flen = 0;
            int corrected = -1;
            int ok = sw_frame_decode(buf, sizeof buf, rs, work, &off, &plen, &flen, &corrected);
            CHECK(ok == 1);
            if (!ok) continue;
            CHECK(plen == len && flen == n);
            CHECK(memcmp(work + off, payload, len) == 0);
            CHECK(rs ? corrected > 0 : corrected == 0);
        }
    }
}

static void test_rejects(void) {
    uint8_t f[SW_FRAME_MAX_LEN + 1];
    uint8_t p[SW_FRAME_MAX_PAYLOAD + 1] = {0};
    CHECK(sw_frame_encode(p, 0, 1, f, sizeof f) == 0);
    CHECK(sw_frame_encode(p, SW_FRAME_MAX_PAYLOAD + 1, 1, f, sizeof f) == 0);
    CHECK(sw_frame_encode(p, 10, 1, f, 10) == 0); // capacity too small

    uint8_t noise[300], work[SW_FRAME_MAX_LEN];
    for (size_t i = 0; i < sizeof noise; i++) noise[i] = (uint8_t)(i * 97 + 13);
    size_t off, plen, flen;
    int corr;
    CHECK(sw_frame_decode(noise, sizeof noise, 1, work, &off, &plen, &flen, &corr) == 0);
    CHECK(sw_frame_decode(noise, 10, 1, work, &off, &plen, &flen, &corr) == 0);
}

int main(void) {
    test_golden_layout();
    test_decode_with_trailing_bytes_and_errors();
    test_rejects();
    if (failures) {
        fprintf(stderr, "%d frame format check(s) failed\n", failures);
        return 1;
    }
    printf("All CLI frame format tests passed.\n");
    return 0;
}
