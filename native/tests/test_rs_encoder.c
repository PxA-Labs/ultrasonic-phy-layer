// Comprehensive unit tests for GF(2^8) arithmetic and Reed-Solomon encoder.

#include "soundwave/rs.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

static void test_gf_arithmetic(void) {
    printf("Testing GF(2^8) arithmetic...\n");

    // Addition & Subtraction
    for (int a = 0; a < 256; a++) {
        for (int b = 0; b < 256; b++) {
            uint8_t add_val = gf_add((uint8_t)a, (uint8_t)b);
            uint8_t sub_val = gf_sub((uint8_t)a, (uint8_t)b);
            assert(add_val == (a ^ b));
            assert(sub_val == add_val);
        }
        assert(gf_add((uint8_t)a, (uint8_t)a) == 0);
    }

    // Multiplication & Division identities
    for (int a = 0; a < 256; a++) {
        assert(gf_mul((uint8_t)a, 0) == 0);
        assert(gf_mul(0, (uint8_t)a) == 0);
        assert(gf_mul((uint8_t)a, 1) == (uint8_t)a);
        assert(gf_mul(1, (uint8_t)a) == (uint8_t)a);
        assert(gf_div((uint8_t)a, 1) == (uint8_t)a);
    }

    // Multiplicative Inverses
    for (int a = 1; a < 256; a++) {
        uint8_t inv = gf_inv((uint8_t)a);
        uint8_t prod = gf_mul((uint8_t)a, inv);
        assert(prod == 1);
        assert(gf_div((uint8_t)a, (uint8_t)a) == 1);
    }

    // Powers & Log/Exp consistency
    for (int a = 1; a < 256; a++) {
        assert(gf_pow((uint8_t)a, 0) == 1);
        assert(gf_pow((uint8_t)a, 1) == (uint8_t)a);
        uint8_t inv_pow = gf_pow((uint8_t)a, -1);
        assert(inv_pow == gf_inv((uint8_t)a));
    }

    // Distributive Property: a * (b ^ c) == (a * b) ^ (a * c)
    for (int a = 1; a < 16; a++) {
        for (int b = 0; b < 16; b++) {
            for (int c = 0; c < 16; c++) {
                uint8_t lhs = gf_mul((uint8_t)a, gf_add((uint8_t)b, (uint8_t)c));
                uint8_t rhs = gf_add(gf_mul((uint8_t)a, (uint8_t)b), gf_mul((uint8_t)a, (uint8_t)c));
                assert(lhs == rhs);
            }
        }
    }

    printf("PASS: GF(2^8) arithmetic verified.\n");
}

static void test_generator_polynomial(void) {
    printf("Testing RS generator polynomial computation...\n");

    // RS(255, 223) -> 32 parity symbols
    uint8_t g32[33];
    rs_compute_generator_poly(255, 223, g32);
    assert(g32[0] == 1);

    // Verify roots alpha^1 to alpha^32 evaluate to zero on g32(x)
    for (int i = 1; i <= 32; i++) {
        uint8_t alpha_i = gf_pow(2, i); // alpha = 2 in GF(2^8) Rijndael
        uint8_t val = gf_poly_eval(g32, 33, alpha_i);
        assert(val == 0);
    }

    // RS(63, 47) -> 16 parity symbols
    uint8_t g16[17];
    rs_compute_generator_poly(63, 47, g16);
    assert(g16[0] == 1);

    for (int i = 1; i <= 16; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(g16, 17, alpha_i);
        assert(val == 0);
    }

    // RS(31, 21) -> 10 parity symbols
    uint8_t g10[11];
    rs_compute_generator_poly(31, 21, g10);
    assert(g10[0] == 1);

    for (int i = 1; i <= 10; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(g10, 11, alpha_i);
        assert(val == 0);
    }

    printf("PASS: Generator polynomials roots verified.\n");
}

static void test_rs255_223_encoding(void) {
    printf("Testing RS(255, 223) encoder...\n");

    uint8_t data[223];
    uint8_t parity[32];
    uint8_t codeword[255];

    // Case 1: All zeros message -> parity should be all zeros
    memset(data, 0, sizeof(data));
    rs_encode(data, 223, parity, 255);
    for (int i = 0; i < 32; i++) {
        assert(parity[i] == 0);
    }

    // Case 2: All 0xFF message
    memset(data, 0xFF, sizeof(data));
    rs_encode(data, 223, parity, 255);

    memcpy(codeword, data, 223);
    memcpy(codeword + 223, parity, 32);

    // Verify all 32 roots of codeword evaluate to zero
    for (int i = 1; i <= 32; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(codeword, 255, alpha_i);
        assert(val == 0);
    }

    // Case 3: Incremental pattern message
    for (int i = 0; i < 223; i++) {
        data[i] = (uint8_t)(i * 7 + 13);
    }
    rs_encode(data, 223, parity, 255);

    memcpy(codeword, data, 223);
    memcpy(codeword + 223, parity, 32);

    for (int i = 1; i <= 32; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(codeword, 255, alpha_i);
        assert(val == 0);
    }

    // Syndrome detection test: corrupt 1 byte, evaluate roots -> must be non-zero!
    codeword[10] ^= 0x01;
    int non_zero_syndrome = 0;
    for (int i = 1; i <= 32; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        if (gf_poly_eval(codeword, 255, alpha_i) != 0) {
            non_zero_syndrome = 1;
            break;
        }
    }
    assert(non_zero_syndrome == 1);

    printf("PASS: RS(255, 223) encoding & root evaluation verified.\n");
}

static void test_rs_shortened_encoding(void) {
    printf("Testing shortened RS codes...\n");

    // Test RS(63, 47)
    uint8_t data47[47];
    uint8_t parity16[16];
    uint8_t codeword63[63];

    for (int i = 0; i < 47; i++) {
        data47[i] = (uint8_t)(i + 1);
    }
    rs_encode_shortened(data47, 47, parity16);

    memcpy(codeword63, data47, 47);
    memcpy(codeword63 + 47, parity16, 16);

    for (int i = 1; i <= 16; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(codeword63, 63, alpha_i);
        assert(val == 0);
    }

    // Test RS(31, 21)
    uint8_t data21[21];
    uint8_t parity10[10];
    uint8_t codeword31[31];

    for (int i = 0; i < 21; i++) {
        data21[i] = (uint8_t)(i * 3 + 5);
    }
    rs_encode_shortened(data21, 21, parity10);

    memcpy(codeword31, data21, 21);
    memcpy(codeword31 + 21, parity10, 10);

    for (int i = 1; i <= 10; i++) {
        uint8_t alpha_i = gf_pow(2, i);
        uint8_t val = gf_poly_eval(codeword31, 31, alpha_i);
        assert(val == 0);
    }

    printf("PASS: Shortened RS codes verified.\n");
}

static void test_golden_vector(void) {
    printf("Testing golden vector reproducibility...\n");

    uint8_t data[223];
    uint8_t parity1[32];
    uint8_t parity2[32];

    const char* secret_msg = "Soundwave Ultrasonic PHY Layer - Reed-Solomon GF(2^8) Golden Vector Test";
    size_t msg_len = strlen(secret_msg);

    memset(data, 0xAB, sizeof(data));
    memcpy(data, secret_msg, msg_len);

    rs_encode(data, 223, parity1, 255);
    rs_encode(data, 223, parity2, 255);

    // Reproducibility check
    assert(memcmp(parity1, parity2, 32) == 0);

    // Ensure parity is deterministic and non-trivial
    int non_zero_count = 0;
    for (int i = 0; i < 32; i++) {
        if (parity1[i] != 0) non_zero_count++;
    }
    assert(non_zero_count > 25);

    printf("PASS: Golden vector test passed.\n");
}

int main(void) {
    rs_init_generator();

    test_gf_arithmetic();
    test_generator_polynomial();
    test_rs255_223_encoding();
    test_rs_shortened_encoding();
    test_golden_vector();

    printf("All RS encoder unit tests passed successfully!\n");
    return 0;
}
