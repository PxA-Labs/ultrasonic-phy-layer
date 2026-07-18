// Fuzz target: API boundary. Dispatches to random sw_* functions.

#include "soundwave_api.h"
#include <stdint.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
    if (Size < 1) return 0;
    uint8_t cmd = Data[0] % 8;

    switch (cmd) {
    case 0: { uint32_t crc; sw_crc32(Data + 1, Size - 1, &crc); break; }
    case 1: { uint8_t parity[32]; size_t plen = 32; sw_rs_encode(Data + 1, Size - 1, parity, &plen); break; }
    default: break;
    }
    return 0;
}
