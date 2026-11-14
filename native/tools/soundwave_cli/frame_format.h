// Soundwave PHY frame format, shared with the Flutter app
// (soundwave_app/lib/engine/frame_codec.dart). See docs/DEVELOPER_GUIDE.md,
// "PHY frame format".
//
//   [CRC-32, 4 bytes little-endian, over payload][payload][RS parity, 32 bytes]
//
// The RS(255,223) parity covers CRC + payload and is present unless RS is
// disabled. There is no length field: the demodulator returns every symbol in
// its input (including trailing noise), and the decoder takes the shortest
// length whose RS decode (if enabled) and CRC-32 both verify.

#ifndef SOUNDWAVE_CLI_FRAME_FORMAT_H
#define SOUNDWAVE_CLI_FRAME_FORMAT_H

#include <stddef.h>
#include <stdint.h>

#define SW_FRAME_CRC_LEN    4
#define SW_FRAME_PARITY_LEN 32
#define SW_FRAME_MAX_PAYLOAD (223 - SW_FRAME_CRC_LEN) // 219 bytes
#define SW_FRAME_MAX_LEN (SW_FRAME_CRC_LEN + SW_FRAME_MAX_PAYLOAD + SW_FRAME_PARITY_LEN)

// Builds a frame for payload[0..len) into out (capacity cap). Returns the
// frame length, or 0 if len is 0 or > SW_FRAME_MAX_PAYLOAD, or cap is short.
size_t sw_frame_encode(const uint8_t* payload, size_t len, int enable_rs,
                       uint8_t* out, size_t cap);

// Finds and verifies the frame at the start of bytes[0..n). On success
// returns 1 and sets *payload_off / *payload_len (into a corrected copy held
// in work, which needs SW_FRAME_MAX_LEN bytes), *frame_len and
// *errors_corrected. Returns 0 if no length verifies.
int sw_frame_decode(const uint8_t* bytes, size_t n, int enable_rs, uint8_t* work,
                    size_t* payload_off, size_t* payload_len, size_t* frame_len,
                    int* errors_corrected);

#endif
