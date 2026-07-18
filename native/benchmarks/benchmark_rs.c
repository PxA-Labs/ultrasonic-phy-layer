#include "bench_util.h"
#include "soundwave/rs.h"
#include <stdlib.h>
#include <string.h>

int main(void) {
    printf("[\n");
    int first = 1;

    uint8_t data[223];
    uint8_t parity[32];
    size_t n = 255;
    for (int i = 0; i < (int)sizeof(data); i++) data[i] = (uint8_t)(i & 0xFF);

    rs_init_generator();

    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("RS_encode_223B", 10000, { rs_encode(data, 223, parity, n); });
    }

    uint8_t codeword[255];
    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        memcpy(codeword, data, 223);
        rs_encode(data, 223, codeword + 223, n);
        BENCH_BLOCK("RS_decode_255B", 10000, { rs_decode(codeword, n); });
    }

    printf("\n]\n");
    return 0;
}
