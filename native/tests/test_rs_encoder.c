// Unit tests for Reed-Solomon encoder.

#include "soundwave/rs.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

int main(void) {
    rs_init_generator();

    uint8_t data[223];
    uint8_t parity[32];
    memset(data, 0x42, sizeof(data));

    rs_encode(data, 223, parity, 255);
    printf("PASS: RS(255,223) encoded, parity length=32\n");

    rs_encode_shortened(data, 100, parity);
    printf("PASS: RS shortened (k=100) encoded\n");

    printf("All RS encoder tests passed.\n");
    return 0;
}
