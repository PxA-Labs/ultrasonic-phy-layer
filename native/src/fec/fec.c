// FEC module — RS(255,223) encode/decode with convolutional interleaving.

#include "soundwave/fec.h"
#include "soundwave/rs.h"
#include <string.h>

#define INTERLEAVE_BRANCHES 12
#define INTERLEAVE_DEPTH    17

void fec_interleave(const uint8_t* in, size_t len, uint8_t* out) {
    size_t idx = 0;
    for (int b = 0; b < INTERLEAVE_BRANCHES && idx < len; b++) {
        for (int d = 0; d < INTERLEAVE_DEPTH && idx < len; d++) {
            int delay = (INTERLEAVE_DEPTH - 1) * b;
            size_t pos = idx + (size_t)delay;
            if (pos < len) out[pos] = in[idx];
            idx++;
        }
    }
}

void fec_deinterleave(const uint8_t* in, size_t len, uint8_t* out) {
    size_t idx = 0;
    for (int b = 0; b < INTERLEAVE_BRANCHES && idx < len; b++) {
        for (int d = 0; d < INTERLEAVE_DEPTH && idx < len; d++) {
            int delay = (INTERLEAVE_DEPTH - 1) * b;
            size_t pos = idx + (size_t)delay;
            if (pos < len) out[idx] = in[pos];
            idx++;
        }
    }
}

int fec_encode(const uint8_t* data, size_t data_len,
               uint8_t* coded, size_t* coded_len) {
    if (data_len > 223) return -1;
    size_t rs_len = 255;

    // Pad to 223, RS encode (data -> coded)
    uint8_t buf[223];
    memset(buf, 0, 223);
    memcpy(buf, data, data_len);
    rs_encode(buf, data_len, coded, rs_len);

    // Interleave in place
    fec_interleave(coded, rs_len, coded);

    *coded_len = rs_len;
    return 0;
}

int fec_decode(const uint8_t* coded, size_t coded_len,
               uint8_t* data, size_t* data_len, int* errors_corrected) {
    if (coded_len < 255) return -1;

    // Deinterleave
    uint8_t deinterleaved[255];
    fec_deinterleave(coded, coded_len, deinterleaved);

    // RS decode (in-place)
    int errs = rs_decode(deinterleaved, 255);
    if (errors_corrected) *errors_corrected = errs;
    if (errs < 0) return -1;

    memcpy(data, deinterleaved, 223);
    *data_len = 223;
    return errs;
}
