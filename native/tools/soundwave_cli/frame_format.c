// Soundwave PHY frame format (see frame_format.h). Same layout and decode
// rule as soundwave_app/lib/engine/frame_codec.dart.

#include "frame_format.h"
#include "soundwave_api.h"
#include <string.h>

static uint32_t rd_le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

size_t sw_frame_encode(const uint8_t* payload, size_t len, int enable_rs,
                       uint8_t* out, size_t cap) {
    if (!payload || !out || len == 0 || len > SW_FRAME_MAX_PAYLOAD) return 0;
    size_t total = SW_FRAME_CRC_LEN + len + (enable_rs ? SW_FRAME_PARITY_LEN : 0);
    if (cap < total) return 0;
    uint32_t crc = 0;
    if (sw_crc32(payload, len, &crc) != SW_OK) return 0;
    out[0] = (uint8_t)(crc & 0xFF);
    out[1] = (uint8_t)((crc >> 8) & 0xFF);
    out[2] = (uint8_t)((crc >> 16) & 0xFF);
    out[3] = (uint8_t)((crc >> 24) & 0xFF);
    memcpy(out + SW_FRAME_CRC_LEN, payload, len);
    if (enable_rs) {
        size_t plen = SW_FRAME_PARITY_LEN;
        if (sw_rs_encode(out, SW_FRAME_CRC_LEN + len, out + SW_FRAME_CRC_LEN + len,
                         &plen) != SW_OK ||
            plen != SW_FRAME_PARITY_LEN)
            return 0;
    }
    return total;
}

int sw_frame_decode(const uint8_t* bytes, size_t n, int enable_rs, uint8_t* work,
                    size_t* payload_off, size_t* payload_len, size_t* frame_len,
                    int* errors_corrected) {
    if (!bytes || !work || !payload_off || !payload_len || !frame_len || !errors_corrected)
        return 0;
    size_t overhead = SW_FRAME_CRC_LEN + (enable_rs ? SW_FRAME_PARITY_LEN : 0);
    size_t max_len = overhead + SW_FRAME_MAX_PAYLOAD;
    if (n < max_len) max_len = n;
    for (size_t len = overhead + 1; len <= max_len; len++) {
        size_t data_len = len - (enable_rs ? SW_FRAME_PARITY_LEN : 0);
        memcpy(work, bytes, data_len);
        int corrected = 0;
        if (enable_rs) {
            size_t k = data_len;
            if (sw_rs_decode(work, &k, bytes + data_len, SW_FRAME_PARITY_LEN, &corrected) != SW_OK)
                continue; // uncorrectable at this length
        }
        uint32_t crc = 0;
        if (sw_crc32(work + SW_FRAME_CRC_LEN, data_len - SW_FRAME_CRC_LEN, &crc) != SW_OK)
            continue;
        if (crc == rd_le32(work)) {
            *payload_off = SW_FRAME_CRC_LEN;
            *payload_len = data_len - SW_FRAME_CRC_LEN;
            *frame_len = len;
            *errors_corrected = corrected;
            return 1;
        }
    }
    return 0;
}
