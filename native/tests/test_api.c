// Comprehensive unit tests for public C API boundary.

#include "soundwave_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <math.h>

void test_version_and_crc(void) {
    const char* ver = sw_version();
    assert(strcmp(ver, "1.0.0") == 0);
    printf("PASS: version = %s\n", ver);

    uint32_t crc;
    int ret = sw_crc32((const uint8_t*)"hello", 5, &crc);
    assert(ret == SW_OK);
    assert(crc == 0x3610A686);
    printf("PASS: crc32(\"hello\") = 0x%08X\n", crc);

    // Bad params
    ret = sw_crc32(NULL, 5, &crc);
    assert(ret == SW_ERR_BAD_PARAM);
    ret = sw_crc32((const uint8_t*)"hello", 5, NULL);
    assert(ret == SW_ERR_BAD_PARAM);
    printf("PASS: bad params return SW_ERR_BAD_PARAM\n");
}

void test_rs_codec_api(void) {
    printf("Testing Reed-Solomon C API...\n");
    uint8_t original_data[223];
    for (int i = 0; i < 223; i++) original_data[i] = (uint8_t)(i + 1);

    uint8_t parity[32];
    size_t parity_len = 0;
    int ret = sw_rs_encode(original_data, 223, parity, &parity_len);
    assert(ret == SW_OK);
    assert(parity_len == 32);

    // Introduce 5 errors in data and 2 errors in parity
    uint8_t received_data[223];
    memcpy(received_data, original_data, 223);
    received_data[10] ^= 0xFF;
    received_data[20] ^= 0xAA;
    received_data[30] ^= 0x55;
    received_data[40] ^= 0x0F;
    received_data[50] ^= 0xF0;

    uint8_t received_parity[32];
    memcpy(received_parity, parity, 32);
    received_parity[5] ^= 0x12;
    received_parity[15] ^= 0x34;

    size_t data_len = 223;
    int errors_corrected = 0;
    ret = sw_rs_decode(received_data, &data_len, received_parity, 32, &errors_corrected);
    assert(ret == SW_OK);
    assert(errors_corrected == 7);
    assert(data_len == 223);
    assert(memcmp(received_data, original_data, 223) == 0);

    // Bad parameters
    ret = sw_rs_decode(NULL, &data_len, received_parity, 32, &errors_corrected);
    assert(ret == SW_ERR_BAD_PARAM);
    ret = sw_rs_decode(received_data, NULL, received_parity, 32, &errors_corrected);
    assert(ret == SW_ERR_BAD_PARAM);

    // Test uncorrectable errors (>16 errors)
    memcpy(received_data, original_data, 223);
    for (int i = 0; i < 20; i++) {
        received_data[i] ^= 0xFF;
    }
    ret = sw_rs_decode(received_data, &data_len, parity, 32, &errors_corrected);
    assert(ret == SW_ERR_DECODE);

    printf("PASS: Reed-Solomon C API tests completed.\n");
}

void test_sync_and_cfo_api(void) {
    printf("Testing sync and CFO APIs...\n");

    sw_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.sample_rate = 44100;
    cfg.modulation = 0; // CSS
    cfg.symbol_duration = 0.02f;
    cfg.carrier_freq = 19000.0f;
    cfg.bandwidth = 2000.0f;
    cfg.amplitude = 0.8f;

    uint8_t bits[4] = { 0xAA, 0xBB, 0xCC, 0xDD };
    size_t sample_len = 1000000;
    float* samples = (float*)malloc(sample_len * sizeof(float));
    assert(samples != NULL);

    int ret = sw_css_modulate(bits, 32, cfg, samples, &sample_len);
    assert(ret == SW_OK);

    // Shift signal by 200 samples
    size_t rx_len = sample_len + 400;
    float* rx = (float*)calloc(rx_len, sizeof(float));
    memcpy(rx + 200, samples, sample_len * sizeof(float));

    size_t start = 0;
    float snr = 0.0f;
    ret = sw_detect_frame(rx, rx_len, cfg, &start, &snr);
    assert(ret == SW_OK);
    // Matched filter CSS should be extremely accurate
    assert(start == 200);

    // Estimate CFO
    float cfo = 0.0f;
    ret = sw_estimate_cfo(rx, rx_len, cfg, &cfo);
    assert(ret == SW_OK);

    // Bad params
    ret = sw_detect_frame(NULL, rx_len, cfg, &start, &snr);
    assert(ret == SW_ERR_BAD_PARAM);
    ret = sw_estimate_cfo(NULL, rx_len, cfg, &cfo);
    assert(ret == SW_ERR_BAD_PARAM);

    free(samples);
    free(rx);
    printf("PASS: sync and CFO APIs completed.\n");
}

int main(void) {
    test_version_and_crc();
    test_rs_codec_api();
    test_sync_and_cfo_api();
    printf("All API tests passed.\n");
    return 0;
}
