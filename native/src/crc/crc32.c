// CRC-32 (IEEE 802.3) implementation using a 256-entry lookup table.
// Polynomial: 0xEDB88320 (reflected). Compatible with zip, ethernet, etc.

#include "soundwave/crc.h"

static uint32_t crc_table[256];
static int      table_initialized = 0;

void crc32_init_table(void) {
    if (table_initialized) return;
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++)
            crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
        crc_table[i] = crc;
    }
    table_initialized = 1;
}

uint32_t crc32_compute(const uint8_t* data, size_t len) {
    crc32_init_table();
    return crc32_compute_fast(data, len);
}

uint32_t crc32_compute_fast(const uint8_t* data, size_t len) {
    if (len == 0 || data == NULL) {
        return 0x00000000u;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++)
        crc = crc_table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

void crc32_append(uint8_t* buffer, size_t data_len) {
    if (buffer == NULL) return;
    uint32_t crc = crc32_compute(buffer, data_len);
    buffer[data_len + 0] = (uint8_t)((crc >> 24) & 0xFF);
    buffer[data_len + 1] = (uint8_t)((crc >> 16) & 0xFF);
    buffer[data_len + 2] = (uint8_t)((crc >> 8) & 0xFF);
    buffer[data_len + 3] = (uint8_t)(crc & 0xFF);
}

int crc32_verify(const uint8_t* data, size_t len) {
    if (data == NULL || len < 4) return 0;
    size_t data_len = len - 4;
    uint32_t computed_crc = crc32_compute(data, data_len);
    uint32_t stored_crc = ((uint32_t)data[data_len + 0] << 24)
                        | ((uint32_t)data[data_len + 1] << 16)
                        | ((uint32_t)data[data_len + 2] << 8)
                        |  (uint32_t)data[data_len + 3];
    return (computed_crc == stored_crc) ? 1 : 0;
}

