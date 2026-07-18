// Unit tests for the public C API boundary.

#include "soundwave_api.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    // Version
    const char* ver = sw_version();
    assert(strcmp(ver, "1.0.0") == 0);
    printf("PASS: version = %s\n", ver);

    // CRC-32
    uint32_t crc;
    int ret = sw_crc32((const uint8_t*)"hello", 5, &crc);
    assert(ret == SW_OK);
    assert(crc == 0x3610A686);
    printf("PASS: crc32(\"hello\") = 0x%08X\n", crc);

    // Null param
    ret = sw_crc32(NULL, 5, &crc);
    assert(ret == SW_ERR_BAD_PARAM);
    printf("PASS: null param returns SW_ERR_BAD_PARAM\n");

    printf("All API tests passed.\n");
    return 0;
}
