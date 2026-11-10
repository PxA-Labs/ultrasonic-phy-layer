// Fuzz target: CRC-32 (IEEE 802.3).
// Properties:
//   * crc32_compute() == crc32_compute_fast() == sw_crc32()   (differential)
//   * crc32_verify(append(x)) succeeds, and fails after any single-bit flip
//     (CRC-32 detects all 1-bit errors).

#include "fuzz_common.h"
#include "soundwave/crc.h"
#include "soundwave_api.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    uint32_t a = crc32_compute(data, size);
    crc32_init_table();
    uint32_t b = crc32_compute_fast(data, size);
    uint32_t c = 0;
    FZ_CHECK(sw_crc32(data, size, &c) == SW_OK);
    FZ_CHECK(a == b && b == c);

    if (size == 0 || size > 4096) return 0;
    uint8_t* framed = (uint8_t*)malloc(size + 4);
    if (!framed) return 0;
    memcpy(framed, data, size);
    crc32_append(framed, size);
    FZ_CHECK(crc32_verify(framed, size + 4) == 1);

    size_t bit = (size_t)data[0] * 131u % ((size + 4) * 8);
    framed[bit / 8] ^= (uint8_t)(1u << (bit % 8));
    FZ_CHECK(crc32_verify(framed, size + 4) == 0);
    free(framed);
    return 0;
}
