// Reed-Solomon decoder: Berlekamp-Massey, Chien search, Forney algorithm.
// Supports RS(255,223), RS(63,47), RS(31,21), and general RS(n, k) over GF(256).

#include "soundwave/rs.h"
#include <string.h>

#define RS_MAX_ERRORS 32

// Helper to determine number of parity symbols 2t from block length n
static size_t get_num_parity(size_t n) {
    if (n == 63) return 16;
    if (n == 31) return 10;
    return 32; // Default for n = 255 or general
}

// 1. Syndrome Computation
void rs_compute_syndromes(const uint8_t* r, size_t n, uint8_t* S) {
    if (!r || !S || n == 0) return;
    size_t num_parity = get_num_parity(n);
    for (size_t j = 0; j < num_parity; j++) {
        uint8_t alpha_j = gf_pow(2, (int)(j + 1));
        S[j] = gf_poly_eval(r, n, alpha_j);
    }
}

// Check if all syndromes are zero
static int rs_syndromes_all_zero(const uint8_t* S, size_t num_parity) {
    for (size_t j = 0; j < num_parity; j++) {
        if (S[j] != 0) return 0;
    }
    return 1;
}

// 2. Berlekamp-Massey Algorithm for arbitrary number of syndromes (2t)
int rs_berlekamp_massey_len(const uint8_t* S, int num_syndromes, uint8_t* lambda, uint8_t* omega) {
    if (!S || !lambda || !omega || num_syndromes <= 0 || num_syndromes > 64) return -1;

    memset(lambda, 0, (size_t)(num_syndromes + 1));
    memset(omega, 0, (size_t)(num_syndromes + 1));

    uint8_t b_poly[65] = {0};
    uint8_t temp_lambda[65] = {0};

    lambda[0] = 1;
    b_poly[0] = 1;

    int L = 0;
    int m = 1;
    uint8_t b = 1;

    for (int r = 0; r < num_syndromes; r++) {
        // Discrepancy delta = sum_{i=0..L} lambda[i] * S[r - i]
        uint8_t delta = S[r];
        for (int i = 1; i <= L && i <= r; i++) {
            delta = gf_add(delta, gf_mul(lambda[i], S[r - i]));
        }

        if (delta == 0) {
            m++;
        } else {
            memcpy(temp_lambda, lambda, (size_t)(num_syndromes + 1));
            uint8_t d = gf_div(delta, b);

            // lambda(x) = lambda(x) ^ (d * x^m * B(x))
            for (int j = 0; j <= num_syndromes - m; j++) {
                if (b_poly[j] != 0) {
                    lambda[j + m] = gf_add(lambda[j + m], gf_mul(d, b_poly[j]));
                }
            }

            if (2 * L <= r) {
                L = r + 1 - L;
                memcpy(b_poly, temp_lambda, (size_t)(num_syndromes + 1));
                b = delta;
                m = 1;
            } else {
                m++;
            }
        }
    }

    int t = num_syndromes / 2;
    if (L < 0 || L > t) return -1; // Uncorrectable

    // Compute error evaluator polynomial omega(x) = S(x) * lambda(x) mod x^(num_syndromes)
    for (int k = 0; k < num_syndromes; k++) {
        uint8_t val = 0;
        int limit = (k < L) ? k : L;
        for (int i = 0; i <= limit; i++) {
            val = gf_add(val, gf_mul(lambda[i], S[k - i]));
        }
        omega[k] = val;
    }

    return L;
}

int rs_berlekamp_massey(const uint8_t* S, uint8_t* lambda, uint8_t* omega) {
    return rs_berlekamp_massey_len(S, 32, lambda, omega);
}

// 3. Chien Search
void rs_chien_search_n(const uint8_t* lambda, int degree, size_t n,
                       int* error_positions, int* count) {
    if (!lambda || !error_positions || !count || degree < 0 || n == 0) {
        if (count) *count = 0;
        return;
    }

    *count = 0;
    if (degree == 0) return;

    for (size_t p = 0; p < n; p++) {
        // Position p in array corresponding to power n - 1 - p of x
        int exp_val = (int)(255 - ((n - 1 - p) % 255)) % 255;
        uint8_t inv_X = gf_pow(2, exp_val);

        uint8_t val = lambda[0];
        uint8_t inv_X_pow = 1;
        for (int j = 1; j <= degree; j++) {
            inv_X_pow = gf_mul(inv_X_pow, inv_X);
            val = gf_add(val, gf_mul(lambda[j], inv_X_pow));
        }

        if (val == 0) {
            if (*count < RS_MAX_ERRORS) {
                error_positions[(*count)++] = (int)p;
            } else {
                *count = RS_MAX_ERRORS + 1; // Indicate overflow
                break;
            }
        }
    }
}

void rs_chien_search(const uint8_t* lambda, int degree,
                     int* error_positions, int* count) {
    rs_chien_search_n(lambda, degree, 255, error_positions, count);
}

// 4. Forney Algorithm
void rs_forney_n(const uint8_t* omega, const uint8_t* lambda,
                 const int* positions, int count, size_t n, uint8_t* magnitudes) {
    if (!omega || !lambda || !positions || !magnitudes || count <= 0 || n == 0) return;

    size_t num_parity = get_num_parity(n);

    for (int i = 0; i < count; i++) {
        int pos = positions[i];
        int exp_val = (int)(255 - ((n - 1 - (size_t)pos) % 255)) % 255;
        uint8_t inv_X = gf_pow(2, exp_val);

        // Evaluate omega(X^-1)
        uint8_t omega_val = omega[0];
        uint8_t inv_X_pow = 1;
        for (size_t j = 1; j < num_parity; j++) {
            inv_X_pow = gf_mul(inv_X_pow, inv_X);
            omega_val = gf_add(omega_val, gf_mul(omega[j], inv_X_pow));
        }

        // Evaluate lambda'(X^-1) (formal derivative, only odd power terms)
        uint8_t lambda_prime_val = 0;
        inv_X_pow = 1; // inv_X^0 for j=1
        uint8_t inv_X_sq = gf_mul(inv_X, inv_X);

        for (int j = 1; j <= (int)num_parity && j <= 63; j += 2) {
            lambda_prime_val = gf_add(lambda_prime_val, gf_mul(lambda[j], inv_X_pow));
            inv_X_pow = gf_mul(inv_X_pow, inv_X_sq);
        }

        if (lambda_prime_val == 0) {
            magnitudes[i] = 0;
        } else {
            magnitudes[i] = gf_div(omega_val, lambda_prime_val);
        }
    }
}

void rs_forney(const uint8_t* omega, const uint8_t* lambda,
               int* positions, int count, uint8_t* magnitudes) {
    rs_forney_n(omega, lambda, positions, count, 255, magnitudes);
}

// 5. Full Decoder Integration
int rs_decode(uint8_t* r, size_t n) {
    if (!r || n == 0 || n > 255) return -1;

    size_t num_parity = get_num_parity(n);
    uint8_t S[64] = {0};
    uint8_t lambda[65] = {0};
    uint8_t omega[65] = {0};
    int error_pos[64] = {0};
    int error_count = 0;
    uint8_t error_mag[64] = {0};

    // 1. Compute syndromes
    rs_compute_syndromes(r, n, S);

    // If all syndromes zero -> no errors
    if (rs_syndromes_all_zero(S, num_parity)) {
        return 0;
    }

    // 2. Berlekamp-Massey Algorithm
    int num_errors = rs_berlekamp_massey_len(S, (int)num_parity, lambda, omega);
    if (num_errors <= 0 || num_errors > (int)(num_parity / 2)) {
        return -1;
    }

    // 3. Chien Search
    rs_chien_search_n(lambda, num_errors, n, error_pos, &error_count);
    if (error_count != num_errors) {
        return -1; // Uncorrectable error position count mismatch
    }

    // 4. Forney Algorithm
    rs_forney_n(omega, lambda, error_pos, error_count, n, error_mag);

    // 5. Apply error corrections
    for (int i = 0; i < error_count; i++) {
        r[error_pos[i]] ^= error_mag[i];
    }

    // 6. Re-verify syndromes to prevent false positive corrections
    rs_compute_syndromes(r, n, S);
    if (!rs_syndromes_all_zero(S, num_parity)) {
        // Revert changes if re-verification failed
        for (int i = 0; i < error_count; i++) {
            r[error_pos[i]] ^= error_mag[i];
        }
        return -1;
    }

    return error_count;
}
