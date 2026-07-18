#include "bench_util.h"
#include "soundwave/crc.h"
#include <stdint.h>

int main(void) {
    printf("[\n");
    int first = 1;

    uint8_t buf1[1024];
    uint8_t buf64[65536];
    for (int i = 0; i < (int)sizeof(buf1); i++) buf1[i] = (uint8_t)(i & 0xFF);
    for (int i = 0; i < (int)sizeof(buf64); i++) buf64[i] = (uint8_t)(i & 0xFF);

    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("CRC32_64B", 100000, { volatile uint32_t crc = crc32_compute(buf1, 64); (void)crc; });
    }
    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("CRC32_1KB", 50000, { volatile uint32_t crc = crc32_compute(buf1, 1024); (void)crc; });
    }
    for (int trial = 0; trial < 3; trial++) {
        if (!first) printf(",\n"); first = 0;
        BENCH_BLOCK("CRC32_64KB", 5000, { volatile uint32_t crc = crc32_compute(buf64, 65536); (void)crc; });
    }

    printf("\n]\n");
    return 0;
}
