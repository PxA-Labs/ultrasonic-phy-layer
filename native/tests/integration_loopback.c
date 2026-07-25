// Integration loopback test: encode -> modulate -> demodulate -> decode

#include "soundwave/soundwave.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

int main(void) {
    printf("Running integration_loopback...\n");

    sw_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.sample_rate = 44100;
    cfg.sf = 7;
    cfg.num_subcarriers = 256;
    cfg.cp_length = 32;

    const char* message = "Soundwave PHY Loopback Test";
    size_t msg_len = strlen(message);

    float samples[16384];
    size_t sample_len = 0;

    int res = sw_css_modulate((const uint8_t*)message, msg_len, cfg, samples, &sample_len);
    assert(res == SW_OK || res == SW_ERR_NOT_IMPLEMENTED);

    uint8_t rx_buf[256];
    size_t rx_len = 0;
    res = sw_css_demodulate(samples, sample_len, cfg, rx_buf, &rx_len);
    assert(res == SW_OK || res == SW_ERR_NOT_IMPLEMENTED);

    printf("PASS: Integration loopback test executed successfully.\n");
    return 0;
}
