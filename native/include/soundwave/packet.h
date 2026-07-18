#ifndef SOUNDWAVE_PACKET_H
#define SOUNDWAVE_PACKET_H
// Packet framing — preamble, sync word, header, payload, and CRC-32 trailer.

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint16_t sync_word;    // 2-byte sync word (default 0xA53C)
    size_t max_payload;    // Maximum payload bytes (default 256)
    int preamble_len;      // Preamble length in bytes (default 64)
    int header_len;        // Header length in bytes (default 8)
} packet_config_t;

void packet_init(packet_config_t* cfg);

// Build a frame: [preamble][sync][header][payload][CRC32].
// Returns 0 on success, -1 on error.
int packet_encode(const packet_config_t* cfg, const uint8_t* payload, size_t payload_len,
                  uint8_t* frame, size_t frame_cap, size_t* frame_len);

// Parse and validate a frame. Returns 0 on success, -1 on error.
int packet_decode(const packet_config_t* cfg, const uint8_t* frame, size_t frame_len,
                  uint8_t* payload, size_t payload_cap, size_t* payload_len);

#endif
