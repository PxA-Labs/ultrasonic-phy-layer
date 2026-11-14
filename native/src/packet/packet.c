// Packet framing — preamble, sync word, header, CRC-32 trailer, and payload.

#include "soundwave/packet.h"
#include "soundwave/crc.h"
#include <string.h>

// Header layout: [len:1][flags:1][reserved...]. The length field is one byte,
// so payloads are limited to 255 bytes (a 256-byte payload used to encode as
// length 0 and could never be decoded).
#define PACKET_MAX_PAYLOAD   255
#define PACKET_MIN_HEADER    2
#define PACKET_MAX_HEADER    256
#define PACKET_MAX_PREAMBLE  4096

static int packet_cfg_valid(const packet_config_t* cfg) {
    return cfg && cfg->preamble_len >= 0 && cfg->preamble_len <= PACKET_MAX_PREAMBLE &&
           cfg->header_len >= PACKET_MIN_HEADER && cfg->header_len <= PACKET_MAX_HEADER &&
           cfg->max_payload <= PACKET_MAX_PAYLOAD;
}

void packet_init(packet_config_t* cfg) {
    if (!cfg) return;
    cfg->sync_word = 0xA53C;
    cfg->max_payload = PACKET_MAX_PAYLOAD;
    cfg->preamble_len = 64;
    cfg->header_len = 8;
}

int packet_encode(const packet_config_t* cfg, const uint8_t* payload, size_t payload_len,
                  uint8_t* frame, size_t frame_cap, size_t* frame_len) {
    if (!packet_cfg_valid(cfg) || !frame || !frame_len || (payload_len && !payload))
        return -1;
    if (payload_len > cfg->max_payload) return -1;
    size_t total = (size_t)cfg->preamble_len + 2 + (size_t)cfg->header_len + payload_len + 4;
    if (frame_cap < total) return -1;

    size_t pos = 0;

    // Preamble (zero-fill)
    memset(frame + pos, 0, (size_t)cfg->preamble_len);
    pos += (size_t)cfg->preamble_len;

    // Sync word
    frame[pos++] = (uint8_t)(cfg->sync_word >> 8);
    frame[pos++] = (uint8_t)(cfg->sync_word & 0xFF);

    // Header
    frame[pos++] = (uint8_t)payload_len;
    frame[pos++] = 0x00;
    memset(frame + pos, 0, (size_t)cfg->header_len - 2);
    pos += (size_t)cfg->header_len - 2;

    // Payload
    if (payload_len) memcpy(frame + pos, payload, payload_len);
    pos += payload_len;

    // CRC-32 over header + payload
    uint32_t crc = crc32_compute(frame + (size_t)cfg->preamble_len + 2,
                                  (size_t)cfg->header_len + payload_len);
    frame[pos++] = (uint8_t)(crc >> 24);
    frame[pos++] = (uint8_t)(crc >> 16);
    frame[pos++] = (uint8_t)(crc >> 8);
    frame[pos++] = (uint8_t)(crc & 0xFF);

    *frame_len = total;
    return 0;
}

int packet_decode(const packet_config_t* cfg, const uint8_t* frame, size_t frame_len,
                  uint8_t* payload, size_t payload_cap, size_t* payload_len) {
    if (!packet_cfg_valid(cfg) || !frame || !payload_len || (payload_cap && !payload))
        return -1;
    size_t min_len = (size_t)cfg->preamble_len + 2 + (size_t)cfg->header_len + 4;
    if (frame_len < min_len) return -1;

    size_t pos = (size_t)cfg->preamble_len;

    // Verify sync word
    uint16_t sync = ((uint16_t)frame[pos] << 8) | frame[pos + 1];
    if (sync != cfg->sync_word) return -1;
    pos += 2;

    // Parse header
    size_t plen = (size_t)frame[pos];
    size_t total = (size_t)cfg->preamble_len + 2 + (size_t)cfg->header_len + plen + 4;
    if (frame_len < total || plen > cfg->max_payload) return -1;

    // Verify CRC-32
    uint32_t crc_stored = ((uint32_t)frame[total - 4] << 24)
                        | ((uint32_t)frame[total - 3] << 16)
                        | ((uint32_t)frame[total - 2] << 8)
                        |  (uint32_t)frame[total - 1];
    uint32_t crc_calc = crc32_compute(frame + (size_t)cfg->preamble_len + 2,
                                       (size_t)cfg->header_len + plen);
    if (crc_calc != crc_stored) return -1;

    // Extract payload
    if (payload_cap < plen) return -1;
    if (plen) memcpy(payload, frame + pos + (size_t)cfg->header_len, plen);
    *payload_len = plen;
    return 0;
}
