// Reed-Solomon codec over GF(256). RS(255,223) with t=16 error correction.
// Supports shortened codes (k < 223). Primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1.

#ifndef SOUNDWAVE_RS_H
#define SOUNDWAVE_RS_H

#include <stddef.h>
#include <stdint.h>

// GF(256) arithmetic
uint8_t gf_mul(uint8_t a, uint8_t b);
uint8_t gf_add(uint8_t a, uint8_t b);
uint8_t gf_inv(uint8_t a);
uint8_t gf_pow(uint8_t a, int exp);

// Initialize generator polynomial (called once).
void    rs_init_generator(void);

// Encode: produce n-k parity bytes from k data bytes.
// parity[0..n-k-1] is filled. n=255, k=223 (or shortened).
void    rs_encode(const uint8_t* data, size_t k, uint8_t* parity, size_t n);

// Shortened RS encode: k <= 223, remaining positions treated as zero.
void    rs_encode_shortened(const uint8_t* data, size_t k, uint8_t* parity);

// Syndrome computation: S[j] = r(alpha^j) for j=0..31.
void    rs_compute_syndromes(const uint8_t* r, size_t n, uint8_t* S);

// Berlekamp-Massey: find error locator polynomial from syndromes.
// Returns number of errors, or -1 if uncorrectable.
int     rs_berlekamp_massey(const uint8_t* S, uint8_t* lambda, uint8_t* omega);

// Chien search: find roots of lambda(x) -> error positions.
void    rs_chien_search(const uint8_t* lambda, int degree,
                        int* error_positions, int* count);

// Forney algorithm: compute error magnitudes at given positions.
void    rs_forney(const uint8_t* omega, const uint8_t* lambda,
                  int* positions, int count, uint8_t* magnitudes);

// Full decode: correct errors in r[0..n-1] in place.
// Returns number of errors corrected, or -1 if uncorrectable.
int     rs_decode(uint8_t* r, size_t n);

#endif // SOUNDWAVE_RS_H
