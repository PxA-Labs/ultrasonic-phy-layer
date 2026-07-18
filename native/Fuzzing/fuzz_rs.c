// Fuzz target: RS codec. Encode random data, corrupt, decode.

#include "soundwave/rs.h"
#include <stdint.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* Data, size_t Size) {
    if (Size < 32) return 0;
    uint8_t codeword[255] = {0};
    size_t k = (Size < 223) ? Size : 223;
    memcpy(codeword, Data, k);
    rs_init_generator();
    rs_encode(codeword, k, codeword + k, 255);
    // Corrupt a few bytes
    for (size_t i = 0; i < 5 && i < Size; i++)
        codeword[Data[i] % 255] ^= 0xFF;
    rs_decode(codeword, 255);
    return 0;
}
