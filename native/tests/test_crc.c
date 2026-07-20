// Unit tests for CRC-32 computation, append, and verification.

#include "soundwave/crc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

int main(void) {
    uint32_t crc;

    // 1. Golden Vector Tests
    crc = crc32_compute((const uint8_t*)"", 0);
    assert(crc == 0x00000000);
    printf("PASS: empty -> 0x%08X\n", crc);

    crc = crc32_compute(NULL, 0);
    assert(crc == 0x00000000);
    printf("PASS: NULL empty -> 0x%08X\n", crc);

    crc = crc32_compute((const uint8_t*)"123456789", 9);
    assert(crc == 0xCBF43926);
    printf("PASS: 123456789 (IEEE 802.3 standard vector) -> 0x%08X\n", crc);

    crc = crc32_compute((const uint8_t*)"hello", 5);
    assert(crc == 0x3610A686);
    printf("PASS: hello -> 0x%08X\n", crc);

    crc = crc32_compute((const uint8_t*)"The quick brown fox jumps over the lazy dog", 43);
    assert(crc == 0x414FA339);
    printf("PASS: fox -> 0x%08X\n", crc);

    const uint8_t sample[4] = {0x01, 0x02, 0x03, 0x04};
    crc = crc32_compute(sample, 4);
    assert(crc == 0xB63CFBCD);
    printf("PASS: {0x01, 0x02, 0x03, 0x04} -> 0x%08X\n", crc);

    // 2. Append and Verify Tests
    uint8_t buf[65540];

    // Empty payload append/verify
    crc32_append(buf, 0);
    assert(crc32_verify(buf, 4) == 1);
    printf("PASS: empty payload append and verify\n");

    // Single-byte payload append/verify
    buf[0] = 0xAB;
    crc32_append(buf, 1);
    assert(crc32_verify(buf, 5) == 1);
    printf("PASS: single byte payload append and verify\n");

    // All-zeros payload (100 bytes)
    memset(buf, 0, 100);
    crc32_append(buf, 100);
    assert(crc32_verify(buf, 104) == 1);
    printf("PASS: 100-byte all-zeros append and verify\n");

    // All-ones payload (100 bytes)
    memset(buf, 0xFF, 100);
    crc32_append(buf, 100);
    assert(crc32_verify(buf, 104) == 1);
    printf("PASS: 100-byte all-ones append and verify\n");

    // Max payload (65535 bytes)
    for (size_t i = 0; i < 65535; i++) {
        buf[i] = (uint8_t)(i & 0xFF);
    }
    crc32_append(buf, 65535);
    assert(crc32_verify(buf, 65539) == 1);
    printf("PASS: max payload (65535 bytes) append and verify\n");

    // 3. Bit-Flip Corruption Detection Tests
    // Single bit flip in payload byte 0
    buf[0] ^= 0x01;
    assert(crc32_verify(buf, 65539) == 0);
    printf("PASS: detected bit-flip in payload\n");

    // Single bit flip in CRC trailer byte 0
    buf[0] ^= 0x01; // restore payload
    assert(crc32_verify(buf, 65539) == 1); // verify valid again
    buf[65535] ^= 0x01; // flip CRC bit
    assert(crc32_verify(buf, 65539) == 0);
    printf("PASS: detected bit-flip in CRC trailer\n");

    // Invalid length verification
    assert(crc32_verify(buf, 3) == 0);
    assert(crc32_verify(NULL, 10) == 0);
    printf("PASS: invalid length and NULL verify rejected\n");

    printf("All CRC-32 tests passed successfully.\n");
    return 0;
}

