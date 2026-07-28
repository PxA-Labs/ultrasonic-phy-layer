// Comprehensive unit tests for Reed-Solomon decoder (BMA, Chien, Forney).

#include "soundwave/rs.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>

// Helper to corrupt 'count' distinct random positions in a codeword
static void corrupt_codeword(uint8_t* codeword, size_t len, int count, unsigned int seed) {
    srand(seed);
    int corrupted = 0;
    int used[256] = {0};
    while (corrupted < count) {
        int pos = rand() % (int)len;
        if (!used[pos]) {
            used[pos] = 1;
            uint8_t noise = (uint8_t)((rand() % 255) + 1); // Non-zero error
            codeword[pos] ^= noise;
            corrupted++;
        }
    }
}

// 1. Test error-free codeword
static void test_no_errors(void) {
    printf("Testing error-free codeword...\n");
    uint8_t codeword[255];
    memset(codeword, 0x42, 223);
    rs_encode(codeword, 223, codeword + 223, 255);

    uint8_t copy[255];
    memcpy(copy, codeword, 255);
    int corrected = rs_decode(copy, 255);
    assert(corrected == 0);
    assert(memcmp(copy, codeword, 255) == 0);
    printf("PASS: Error-free decoding verified.\n");
}

// 2. Test single error correction
static void test_single_error(void) {
    printf("Testing single error correction...\n");
    uint8_t codeword[255];
    for (int i = 0; i < 223; i++) codeword[i] = (uint8_t)(i * 3 + 7);
    rs_encode(codeword, 223, codeword + 223, 255);

    for (int pos = 0; pos < 255; pos += 17) {
        uint8_t copy[255];
        memcpy(copy, codeword, 255);
        copy[pos] ^= 0x5A;
        int corrected = rs_decode(copy, 255);
        assert(corrected == 1);
        assert(memcmp(copy, codeword, 255) == 0);
    }
    printf("PASS: Single error correction verified across positions.\n");
}

// 3. Test multi-error correction up to t=16
static void test_multi_errors(void) {
    printf("Testing multi-error correction (5 errors and 16 errors)...\n");
    uint8_t codeword[255];
    for (int i = 0; i < 223; i++) codeword[i] = (uint8_t)(i * 13 + 3);
    rs_encode(codeword, 223, codeword + 223, 255);

    // 5 random errors
    uint8_t copy5[255];
    memcpy(copy5, codeword, 255);
    corrupt_codeword(copy5, 255, 5, 12345);
    int corrected5 = rs_decode(copy5, 255);
    assert(corrected5 == 5);
    assert(memcmp(copy5, codeword, 255) == 0);

    // 16 random errors (maximum capacity t=16)
    uint8_t copy16[255];
    memcpy(copy16, codeword, 255);
    corrupt_codeword(copy16, 255, 16, 67890);
    int corrected16 = rs_decode(copy16, 255);
    assert(corrected16 == 16);
    assert(memcmp(copy16, codeword, 255) == 0);

    printf("PASS: Multi-error correction (5 & 16 errors) verified.\n");
}

// 4. Test uncorrectable errors (> t=16)
static void test_uncorrectable_errors(void) {
    printf("Testing uncorrectable errors (> 16 errors)...\n");
    uint8_t codeword[255];
    memset(codeword, 0xAB, 223);
    rs_encode(codeword, 223, codeword + 223, 255);

    // 17 random errors (exceeds t=16 capability)
    uint8_t copy17[255];
    memcpy(copy17, codeword, 255);
    corrupt_codeword(copy17, 255, 17, 9999);
    int res = rs_decode(copy17, 255);
    assert(res == -1);

    printf("PASS: Uncorrectable error (>16 errors) correctly rejected (-1).\n");
}

// 5. Test burst errors (16 consecutive errors)
static void test_burst_errors(void) {
    printf("Testing burst error correction (16 consecutive symbols)...\n");
    uint8_t codeword[255];
    for (int i = 0; i < 223; i++) codeword[i] = (uint8_t)(i + 1);
    rs_encode(codeword, 223, codeword + 223, 255);

    uint8_t copy[255];
    memcpy(copy, codeword, 255);
    // Corrupt 16 consecutive symbols starting at index 100
    for (int i = 100; i < 116; i++) {
        copy[i] ^= (uint8_t)(i + 0x33);
    }
    int corrected = rs_decode(copy, 255);
    assert(corrected == 16);
    assert(memcmp(copy, codeword, 255) == 0);

    printf("PASS: Burst error (16 consecutive symbols) corrected.\n");
}

// 6. Test shortened code RS(63, 47) - t=8
static void test_shortened_rs63_47(void) {
    printf("Testing shortened RS(63, 47) decoding (t=8)...\n");
    uint8_t data[47];
    uint8_t parity[16];
    uint8_t codeword[63];

    for (int i = 0; i < 47; i++) data[i] = (uint8_t)(i * 5 + 1);
    rs_encode_shortened(data, 47, parity);
    memcpy(codeword, data, 47);
    memcpy(codeword + 47, parity, 16);

    // 8 random errors in RS(63, 47)
    uint8_t copy[63];
    memcpy(copy, codeword, 63);
    corrupt_codeword(copy, 63, 8, 4321);
    int corrected = rs_decode(copy, 63);
    assert(corrected == 8);
    assert(memcmp(copy, codeword, 63) == 0);

    printf("PASS: Shortened RS(63, 47) decoding verified.\n");
}

// 7. Test shortened code RS(31, 21) - t=5
static void test_shortened_rs31_21(void) {
    printf("Testing shortened RS(31, 21) decoding (t=5)...\n");
    uint8_t data[21];
    uint8_t parity[10];
    uint8_t codeword[31];

    for (int i = 0; i < 21; i++) data[i] = (uint8_t)(i * 7 + 11);
    rs_encode_shortened(data, 21, parity);
    memcpy(codeword, data, 21);
    memcpy(codeword + 21, parity, 10);

    // 5 random errors in RS(31, 21)
    uint8_t copy[31];
    memcpy(copy, codeword, 31);
    corrupt_codeword(copy, 31, 5, 8765);
    int corrected = rs_decode(copy, 31);
    assert(corrected == 5);
    assert(memcmp(copy, codeword, 31) == 0);

    printf("PASS: Shortened RS(31, 21) decoding verified.\n");
}

// 8. Test all-zeros and all-ones codewords
static void test_all_zeros_and_ones(void) {
    printf("Testing all-zeros and all-ones codewords...\n");

    // All-zeros codeword
    uint8_t codeword0[255] = {0};
    rs_encode(codeword0, 223, codeword0 + 223, 255);
    uint8_t copy0[255];
    memcpy(copy0, codeword0, 255);
    corrupt_codeword(copy0, 255, 10, 1111);
    int corr0 = rs_decode(copy0, 255);
    assert(corr0 == 10);
    assert(memcmp(copy0, codeword0, 255) == 0);

    // All-ones data codeword
    uint8_t codeword1[255];
    memset(codeword1, 0xFF, 223);
    rs_encode(codeword1, 223, codeword1 + 223, 255);
    uint8_t copy1[255];
    memcpy(copy1, codeword1, 255);
    corrupt_codeword(copy1, 255, 12, 2222);
    int corr1 = rs_decode(copy1, 255);
    assert(corr1 == 12);
    assert(memcmp(copy1, codeword1, 255) == 0);

    printf("PASS: All-zeros and all-ones codeword decoding verified.\n");
}

int main(void) {
    printf("Starting Reed-Solomon Decoder Unit Tests...\n");
    rs_init_generator();

    test_no_errors();
    test_single_error();
    test_multi_errors();
    test_uncorrectable_errors();
    test_burst_errors();
    test_shortened_rs63_47();
    test_shortened_rs31_21();
    test_all_zeros_and_ones();

    printf("\n=========================================\n");
    printf("ALL REED-SOLOMON DECODER TESTS PASSED 100%%\n");
    printf("=========================================\n");
    return 0;
}
