// Reed-Solomon encoder over GF(256). RS(255,223) with 32 parity symbols.
// Generator polynomial: g(x) = prod(x - alpha^j) for j=0..31.

#include "soundwave/rs.h"
#include <string.h>

// GF(256) lookup tables (generated at init)
static uint8_t gf_log[256], gf_exp[512];

void rs_init_generator(void) {
    // Pre-compute GF(256) log/exp tables
    // ...
}

uint8_t gf_mul(uint8_t a, uint8_t b) {
    if (a == 0 || b == 0) return 0;
    return gf_exp[gf_log[a] + gf_log[b]];
}

uint8_t gf_add(uint8_t a, uint8_t b) { return a ^ b; }

uint8_t gf_inv(uint8_t a) { return gf_exp[255 - gf_log[a]]; }

uint8_t gf_pow(uint8_t a, int exp) {
    if (a == 0) return 0;
    return gf_exp[(gf_log[a] * exp) % 255];
}

void rs_encode(const uint8_t* data, size_t k, uint8_t* parity, size_t n) {
    (void)data; (void)k; (void)parity; (void)n;
    // TODO: implement polynomial division in GF(256)
}

void rs_encode_shortened(const uint8_t* data, size_t k, uint8_t* parity) {
    rs_encode(data, k, parity, 255);
}

void rs_compute_syndromes(const uint8_t* r, size_t n, uint8_t* S) {
    (void)r; (void)n; (void)S;
    // TODO: evaluate r(alpha^j) for j=0..31
}

int rs_berlekamp_massey(const uint8_t* S, uint8_t* lambda, uint8_t* omega) {
    (void)S; (void)lambda; (void)omega;
    return -1; // TODO
}

void rs_chien_search(const uint8_t* lambda, int degree,
                     int* error_positions, int* count) {
    (void)lambda; (void)degree; (void)error_positions; *count = 0;
}

void rs_forney(const uint8_t* omega, const uint8_t* lambda,
               int* positions, int count, uint8_t* magnitudes) {
    (void)omega; (void)lambda; (void)positions; (void)count; (void)magnitudes;
}

int rs_decode(uint8_t* r, size_t n) {
    (void)r; (void)n;
    return -1; // TODO
}
