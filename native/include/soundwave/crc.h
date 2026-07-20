// CRC-32 (IEEE 802.3) computation — table-driven and direct variants.

#ifndef SOUNDWAVE_CRC_H
#define SOUNDWAVE_CRC_H

#include <stddef.h>
#include <stdint.h>

// Compute CRC-32 over data[0..len-1]. Returns the CRC value.
uint32_t crc32_compute(const uint8_t* data, size_t len);

// Pre-compute CRC table (idempotent, called automatically on first use).
void     crc32_init_table(void);

// Fast table-driven CRC-32 (same result as crc32_compute, but must call
// crc32_init_table once first).
uint32_t crc32_compute_fast(const uint8_t* data, size_t len);

// Append 4-byte CRC-32 in big-endian to buffer after data_len bytes.
// Buffer must have capacity for at least data_len + 4 bytes.
void     crc32_append(uint8_t* buffer, size_t data_len);

// Verify CRC-32 trailer on a data buffer of total length len (includes 4-byte CRC).
// Returns 1 if valid, 0 if invalid or len < 4.
int      crc32_verify(const uint8_t* data, size_t len);

#endif // SOUNDWAVE_CRC_H
