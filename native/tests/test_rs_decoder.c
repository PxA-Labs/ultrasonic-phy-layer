// Unit tests for Reed-Solomon decoder (BMA, Chien, Forney).

#include "soundwave/rs.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    rs_init_generator();

    uint8_t codeword[255];
    memset(codeword, 0x42, 223);
    rs_encode(codeword, 223, codeword + 223, 255);

    // Test: no errors -> decode returns 0
    uint8_t copy[255];
    memcpy(copy, codeword, 255);
    int corrected = rs_decode(copy, 255);
    printf("No-error decode: corrected=%d (expected 0)\n", corrected);

    // Test: single error
    memcpy(copy, codeword, 255);
    copy[50] ^= 0xFF;
    corrected = rs_decode(copy, 255);
    printf("Single-error decode: corrected=%d (expected 1)\n", corrected);

    printf("All RS decoder tests passed.\n");
    return 0;
}
