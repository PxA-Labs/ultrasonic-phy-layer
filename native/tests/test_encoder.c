// Unit tests for encoder module (RS + CRC golden vectors)

#include "soundwave/encoder.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

int main(void) {
    printf("Running test_encoder...\n");

    // CRC-32 golden vector test
    uint32_t crc = crc32_compute((const uint8_t*)"123456789", 9);
    assert(crc == 0xCBF43926);
    printf("PASS: CRC-32 123456789 -> 0x%08X\n", crc);

    // RS init and encode test
    rs_init_generator();
    uint8_t data[223];
    uint8_t parity[32];
    memset(data, 0x42, sizeof(data));
    rs_encode(data, 223, parity, 255);

    // Verify parity was generated
    int non_zero = 0;
    for (int i = 0; i < 32; i++) {
        if (parity[i] != 0) non_zero = 1;
    }
    assert(non_zero);
    printf("PASS: RS(255,223) encoding successful\n");

    printf("All test_encoder tests passed successfully.\n");
    return 0;
}
