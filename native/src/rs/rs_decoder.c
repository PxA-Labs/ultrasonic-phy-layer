// Reed-Solomon decoder: Berlekamp-Massey, Chien search, Forney algorithm.
// Corrects up to 16 byte errors in RS(255,223).

#include "soundwave/rs.h"

// (Shared GF tables are defined in rs_encoder.c, declared extern here)

int rs_decode(uint8_t* r, size_t n) {
    uint8_t S[32], lambda[33], omega[33];
    int error_pos[32], error_count;
    uint8_t error_mag[32];

    rs_compute_syndromes(r, n, S);

    int num_errors = rs_berlekamp_massey(S, lambda, omega);
    if (num_errors < 0) return -1;

    rs_chien_search(lambda, num_errors, error_pos, &error_count);
    if (error_count != num_errors) return -1;

    rs_forney(omega, lambda, error_pos, error_count, error_mag);

    for (int i = 0; i < error_count; i++)
        r[error_pos[i]] ^= error_mag[i];

    return error_count;
}
