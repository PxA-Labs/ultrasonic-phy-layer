// FEC module — RS(255,223) encode/decode with block interleaving.

#include "soundwave/fec.h"
#include "soundwave/rs.h"
#include <string.h>

#define FEC_N      255
#define FEC_K      223
#define FEC_NSYM   (FEC_N - FEC_K)
#define FEC_DEPTH  17 // interleaver columns; 255 = 15 x 17

// Column-major read-out of a row-major grid with FEC_DEPTH columns. This is a
// bijection for every len, so no symbol is dropped or duplicated (the previous
// delay-line scheme only covered 204 of 255 positions and left the rest of the
// output uninitialised). `in` and `out` must not alias.
void fec_interleave(const uint8_t* in, size_t len, uint8_t* out) {
    if (!in || !out || in == out) return;
    size_t k = 0;
    for (size_t c = 0; c < FEC_DEPTH; c++)
        for (size_t i = c; i < len; i += FEC_DEPTH) out[k++] = in[i];
}

void fec_deinterleave(const uint8_t* in, size_t len, uint8_t* out) {
    if (!in || !out || in == out) return;
    size_t k = 0;
    for (size_t c = 0; c < FEC_DEPTH; c++)
        for (size_t i = c; i < len; i += FEC_DEPTH) out[i] = in[k++];
}

int fec_encode(const uint8_t* data, size_t data_len,
               uint8_t* coded, size_t* coded_len) {
    if (!coded || !coded_len || data_len > FEC_K || (data_len && !data)) return -1;

    // Systematic codeword: [data zero-padded to 223][32 parity bytes].
    uint8_t codeword[FEC_N];
    memset(codeword, 0, sizeof codeword);
    if (data_len) memcpy(codeword, data, data_len);
    rs_encode(codeword, FEC_K, codeword + FEC_K, FEC_N);

    fec_interleave(codeword, FEC_N, coded);
    *coded_len = FEC_N;
    return 0;
}

int fec_decode(const uint8_t* coded, size_t coded_len,
               uint8_t* data, size_t* data_len, int* errors_corrected) {
    if (errors_corrected) *errors_corrected = -1;
    if (!coded || !data || !data_len || coded_len < FEC_N) return -1;

    uint8_t codeword[FEC_N];
    fec_deinterleave(coded, FEC_N, codeword); // only the first block is used

    int errs = rs_decode_nsym(codeword, FEC_N, FEC_NSYM);
    if (errors_corrected) *errors_corrected = errs;
    if (errs < 0) return -1;

    memcpy(data, codeword, FEC_K);
    *data_len = FEC_K;
    return errs;
}
