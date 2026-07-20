// Reed-Solomon encoder over GF(256). RS(255,223) with 32 parity symbols.
// Primitive polynomial: p(x) = x^8 + x^4 + x^3 + x^2 + 1 (0x11D).
// Generator polynomial: g(x) = prod(x - alpha^i) for i=1..2t (i0 = 1).

#include "soundwave/rs.h"
#include <string.h>

// GF(256) lookup tables (generated at init)
static uint8_t gf_log[256];
static uint8_t gf_exp[512];
static int gf_initialized = 0;

// Cached generator polynomials for common RS parameters
static uint8_t g_rs255_223[33]; // 2t = 32
static uint8_t g_rs63_47[17];   // 2t = 16
static uint8_t g_rs31_21[11];   // 2t = 10
static int rs_initialized = 0;

static void gf_init_tables(void) {
    if (gf_initialized) return;

    uint32_t x = 1;
    for (int i = 0; i < 255; i++) {
        gf_exp[i] = (uint8_t)x;
        gf_log[(uint8_t)x] = (uint8_t)i;
        x <<= 1;
        if (x & 0x100) {
            x ^= 0x11D;
        }
    }
    for (int i = 255; i < 512; i++) {
        gf_exp[i] = gf_exp[i - 255];
    }
    gf_log[0] = 0;
    gf_initialized = 1;
}

uint8_t gf_add(uint8_t a, uint8_t b) {
    return a ^ b;
}

uint8_t gf_sub(uint8_t a, uint8_t b) {
    return a ^ b;
}

uint8_t gf_mul(uint8_t a, uint8_t b) {
    if (!gf_initialized) gf_init_tables();
    if (a == 0 || b == 0) return 0;
    return gf_exp[gf_log[a] + gf_log[b]];
}

uint8_t gf_div(uint8_t a, uint8_t b) {
    if (!gf_initialized) gf_init_tables();
    if (a == 0 || b == 0) return 0;
    int diff = (int)gf_log[a] - (int)gf_log[b];
    if (diff < 0) diff += 255;
    return gf_exp[diff];
}

uint8_t gf_inv(uint8_t a) {
    if (!gf_initialized) gf_init_tables();
    if (a == 0) return 0;
    return gf_exp[255 - gf_log[a]];
}

uint8_t gf_pow(uint8_t a, int exp) {
    if (!gf_initialized) gf_init_tables();
    if (a == 0) return 0;
    if (exp == 0) return 1;
    int log_a = (int)gf_log[a];
    int p = (log_a * exp) % 255;
    if (p < 0) p += 255;
    return gf_exp[p];
}

uint8_t gf_poly_eval(const uint8_t* poly, size_t len, uint8_t x) {
    if (!poly || len == 0) return 0;
    uint8_t val = 0;
    for (size_t i = 0; i < len; i++) {
        val = gf_add(gf_mul(val, x), poly[i]);
    }
    return val;
}

void rs_compute_generator_poly(size_t n, size_t k, uint8_t* g) {
    if (!gf_initialized) gf_init_tables();
    if (!g || n <= k) return;

    size_t num_parity = n - k;
    memset(g, 0, (num_parity + 1) * sizeof(uint8_t));
    g[0] = 1;

    for (size_t i = 0; i < num_parity; i++) {
        uint8_t root = gf_exp[i + 1]; // alpha^(i + 1) for i0 = 1
        g[i + 1] = gf_mul(root, g[i]);
        for (size_t j = i; j >= 1; j--) {
            g[j] = gf_add(g[j], gf_mul(root, g[j - 1]));
        }
    }
}

void rs_init_generator(void) {
    if (!gf_initialized) gf_init_tables();
    if (rs_initialized) return;

    rs_compute_generator_poly(255, 223, g_rs255_223);
    rs_compute_generator_poly(63, 47, g_rs63_47);
    rs_compute_generator_poly(31, 21, g_rs31_21);

    rs_initialized = 1;
}

void rs_encode(const uint8_t* data, size_t k, uint8_t* parity, size_t n) {
    if (!data || !parity || k == 0 || n <= k) return;
    if (!rs_initialized) rs_init_generator();

    size_t num_parity = n - k;
    const uint8_t* g_ptr = NULL;
    uint8_t g_local[256];

    if (num_parity == 32) {
        g_ptr = g_rs255_223;
    } else if (num_parity == 16) {
        g_ptr = g_rs63_47;
    } else if (num_parity == 10) {
        g_ptr = g_rs31_21;
    } else {
        rs_compute_generator_poly(n, k, g_local);
        g_ptr = g_local;
    }

    uint8_t rem[256] = {0};
    for (size_t i = 0; i < k; i++) {
        uint8_t feedback = gf_add(data[i], rem[0]);
        for (size_t j = 0; j < num_parity - 1; j++) {
            rem[j] = gf_add(rem[j + 1], gf_mul(feedback, g_ptr[j + 1]));
        }
        rem[num_parity - 1] = gf_mul(feedback, g_ptr[num_parity]);
    }

    memcpy(parity, rem, num_parity);
}

void rs_encode_shortened(const uint8_t* data, size_t k, uint8_t* parity) {
    if (k == 47) {
        rs_encode(data, 47, parity, 63);
    } else if (k == 21) {
        rs_encode(data, 21, parity, 31);
    } else {
        rs_encode(data, k, parity, k + 32);
    }
}

void rs_compute_syndromes(const uint8_t* r, size_t n, uint8_t* S) {
    if (!r || !S || n == 0) return;
    if (!gf_initialized) gf_init_tables();
    // Default syndromes computation assuming up to 32 parity symbols
    for (size_t j = 0; j < 32; j++) {
        uint8_t alpha_j = gf_exp[j + 1];
        S[j] = gf_poly_eval(r, n, alpha_j);
    }
}

int rs_berlekamp_massey(const uint8_t* S, uint8_t* lambda, uint8_t* omega) {
    (void)S; (void)lambda; (void)omega;
    return -1; // TODO (Issue #18)
}

void rs_chien_search(const uint8_t* lambda, int degree,
                     int* error_positions, int* count) {
    (void)lambda; (void)degree; (void)error_positions; *count = 0;
}

void rs_forney(const uint8_t* omega, const uint8_t* lambda,
               int* positions, int count, uint8_t* magnitudes) {
    (void)omega; (void)lambda; (void)positions; (void)count; (void)magnitudes;
}
