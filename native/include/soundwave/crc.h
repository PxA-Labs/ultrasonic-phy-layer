// CRC-32 (IEEE 802.3) computation — table-driven and direct variants.

#ifndef SOUNDWAVE_CRC_H
#define SOUNDWAVE_CRC_H

#include <stddef.h>
#include <stdint.h>

// Compute CRC-32 over data[0..len-1]. Returns the CRC value (not complemented).
uint32_t crc32_compute(const uint8_t* data, size_t len);

// Pre-compute CRC table (idempotent, called automatically on first use).
void     crc32_init_table(void);

// Fast table-driven CRC-32 (same result as crc32_compute, but must call
// crc32_init_table once first).
uint32_t crc32_compute_fast(const uint8_t* data, size_t len);

#endif // SOUNDWAVE_CRC_H
