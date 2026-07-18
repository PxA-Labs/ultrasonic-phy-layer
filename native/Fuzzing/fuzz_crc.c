// Fuzz target: CRC-32. Feed arbitrary byte sequences.

#include "soundwave/crc.h"
#include <stdint.h>

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
    uint32_t crc = crc32_compute(Data, Size);
    (void)crc;
    return 0;
}
