#ifndef SOUNDWAVE_FEC_H
#define SOUNDWAVE_FEC_H
// Forward Error Correction — Reed-Solomon encode/decode with interleaving.

#include <stddef.h>
#include <stdint.h>

// Interleave data bytes (convolutional) for burst error protection.
void fec_interleave(const uint8_t* in, size_t len, uint8_t* out);
void fec_deinterleave(const uint8_t* in, size_t len, uint8_t* out);

// Encode: RS(255,223) + interleave. coded_len = len + 32 (RS parity).
// Returns 0 on success, -1 on error.
int fec_encode(const uint8_t* data, size_t data_len,
               uint8_t* coded, size_t* coded_len);

// Decode: deinterleave + RS(255,223) decode.
// Returns number of corrected errors, or -1 if uncorrectable.
int fec_decode(const uint8_t* coded, size_t coded_len,
               uint8_t* data, size_t* data_len, int* errors_corrected);

#endif
