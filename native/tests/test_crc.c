// Unit tests for CRC-32 computation.
// Golden values: ""=0x00000000, "hello"=0x3610A686, fox sentence=0x414FA339.

#include "soundwave/crc.h"
#include <stdio.h>
#include <assert.h>

int main(void) {
    uint32_t crc;

    crc = crc32_compute((const uint8_t*)"", 0);
    assert(crc == 0x00000000);
    printf("PASS: empty -> 0x%08X\n", crc);

    crc = crc32_compute((const uint8_t*)"hello", 5);
    assert(crc == 0x3610A686);
    printf("PASS: hello -> 0x%08X\n", crc);

    crc = crc32_compute((const uint8_t*)"The quick brown fox jumps over the lazy dog", 43);
    assert(crc == 0x414FA339);
    printf("PASS: fox -> 0x%08X\n", crc);

    printf("All CRC-32 tests passed.\n");
    return 0;
}
