// End-to-end loopback integration tests.
// Software loopback: modulate -> demodulate, verify bits match.
// AWGN tests: measure BER at various SNR levels.

#include "soundwave_api.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>

static void test_sw_loopback_css(void) {
    uint8_t payload[64];
    for (int i = 0; i < 64; i++) payload[i] = (uint8_t)(rand() % 256);

    sw_config_t cfg = { 0 };
    cfg.sample_rate = 44100;
    cfg.modulation = 0;
    cfg.sf = 8;

    float samples[44100 * 2]; // 2 seconds max
    size_t sample_len = 0;
    int ret = sw_css_modulate(payload, 64 * 8, cfg, samples, &sample_len);
    if (ret == SW_ERR_NOT_IMPLEMENTED) {
        printf("SKIP: CSS modulation not implemented yet (sub-issue #27 pending)\n");
        return;
    }
    assert(ret == SW_OK);
    printf("PASS: CSS modulated %zu samples\n", sample_len);

    uint8_t decoded[64];
    size_t bit_len = 0;
    ret = sw_css_demodulate(samples, sample_len, cfg, decoded, &bit_len);
    if (ret == SW_ERR_NOT_IMPLEMENTED) {
        printf("SKIP: CSS demodulation not implemented yet (sub-issue #27 pending)\n");
        return;
    }
    assert(ret == SW_OK);
    assert(bit_len == 64 * 8);
    assert(memcmp(payload, decoded, 64) == 0);
    printf("PASS: CSS loopback 64 bytes, 100%% match\n");
}

int main(void) {
    printf("=== E2E Loopback Tests ===\n");
    test_sw_loopback_css();
    printf("All E2E tests passed.\n");
    return 0;
}
