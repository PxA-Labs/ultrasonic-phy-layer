// Unit tests for frame synchronization (matched filter, ZC, Schmidl-Cox).

#include "soundwave/sync.h"
#include "soundwave/css.h"
#include "soundwave/ofdm.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

int main(void) {
    printf("Running frame sync tests...\n");

    // 1. Basic matched filter test
    float template[16];
    for (int i = 0; i < 16; i++) template[i] = (float)i;

    float signal[64];
    memset(signal, 0, sizeof(signal));
    memcpy(signal + 20, template, 16 * sizeof(float)); // template at offset 20

    float R[48] = {0};
    sync_matched_filter(signal, 64, template, 16, R);

    size_t peak = 0;
    float noise_var = sync_estimate_noise(signal, 64);
    int detected = sync_detect_preamble(R, 48, 3.0f, noise_var, &peak);
    assert(detected == 1);
    assert(peak == 20);
    printf("PASS: matched filter peak at %zu (expected 20), detected=%d\n", peak, detected);

    // 2. Zadoff-Chu sequence CAZAC verification
    float zc_real[127], zc_imag[127];
    sync_zc_generate(1, 127, zc_real, zc_imag);
    // Constant amplitude check: |zc[n]|^2 == 1.0
    for (int i = 0; i < 127; i++) {
        float amp = zc_real[i] * zc_real[i] + zc_imag[i] * zc_imag[i];
        assert(fabsf(amp - 1.0f) < 1e-4f);
    }
    printf("PASS: ZC(127,1) generated and verified constant amplitude CAZAC property\n");

    // 3. CSS Frame Synchronization end-to-end timing detection
    sw_config_t css_cfg;
    memset(&css_cfg, 0, sizeof(css_cfg));
    css_cfg.sample_rate = 44100;
    css_cfg.sf = 8;
    css_cfg.carrier_freq = 19000.0f;
    css_cfg.bandwidth = 2000.0f;
    css_cfg.symbol_duration = 0.02f;
    css_cfg.amplitude = 0.8f;

    uint8_t payload[8] = { 0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89 };
    sw_signal css_sig = css_modulate(payload, 8 * 8, css_cfg);
    assert(css_sig.data != NULL);

    // Place preamble at offset 500
    size_t offset = 500;
    size_t rx_len = css_sig.length + offset + 200;
    float* rx_samples = (float*)calloc(rx_len, sizeof(float));
    memcpy(rx_samples + offset, css_sig.data, css_sig.length * sizeof(float));

    sync_config_t sync_cfg_css;
    memset(&sync_cfg_css, 0, sizeof(sync_cfg_css));
    sync_cfg_css.mode = 0; // CSS
    sync_cfg_css.threshold = 3.0f;
    sync_cfg_css.matched_filter_len = (int)(css_cfg.symbol_duration * css_cfg.sample_rate + 0.5f);
    sync_cfg_css.carrier_freq = css_cfg.carrier_freq;
    sync_cfg_css.bandwidth = css_cfg.bandwidth;
    sync_cfg_css.sample_rate = (float)css_cfg.sample_rate;

    size_t detected_start = 0;
    float detected_snr = 0.0f;
    int css_sync_ok = sync_detect_frame(rx_samples, rx_len, &sync_cfg_css, &detected_start, &detected_snr);
    assert(css_sync_ok == 1);
    assert(detected_start == offset);
    printf("PASS: CSS frame sync detected at correct offset %zu, SNR = %.2f dB\n", detected_start, detected_snr);

    free(css_sig.data);
    free(rx_samples);

    // 4. OFDM Frame Synchronization end-to-end timing detection
    sw_config_t ofdm_cfg;
    memset(&ofdm_cfg, 0, sizeof(ofdm_cfg));
    ofdm_cfg.sample_rate = 44100;
    ofdm_cfg.num_subcarriers = 256;
    ofdm_cfg.cp_length = 32;
    ofdm_cfg.num_pilots = 16;
    ofdm_cfg.ofdm_modulation = 1; // QPSK
    ofdm_cfg.threshold = 3.0f;

    sw_signal ofdm_sig = ofdm_modulate(payload, 8 * 8, ofdm_cfg);
    assert(ofdm_sig.data != NULL);

    size_t ofdm_offset = 350;
    size_t ofdm_rx_len = ofdm_sig.length + ofdm_offset + 200;
    float* ofdm_rx_samples = (float*)calloc(ofdm_rx_len, sizeof(float));
    memcpy(ofdm_rx_samples + ofdm_offset, ofdm_sig.data, ofdm_sig.length * sizeof(float));

    sync_config_t sync_cfg_ofdm;
    memset(&sync_cfg_ofdm, 0, sizeof(sync_cfg_ofdm));
    sync_cfg_ofdm.mode = 1; // OFDM
    sync_cfg_ofdm.threshold = 3.0f;
    sync_cfg_ofdm.zc_root = 1;
    sync_cfg_ofdm.zc_length = ofdm_cfg.num_subcarriers / 2 - ofdm_cfg.num_subcarriers / 8 - 1;
    sync_cfg_ofdm.matched_filter_len = ofdm_cfg.num_subcarriers + ofdm_cfg.cp_length;
    sync_cfg_ofdm.carrier_freq = ofdm_cfg.carrier_freq;
    sync_cfg_ofdm.bandwidth = ofdm_cfg.bandwidth;
    sync_cfg_ofdm.sample_rate = (float)ofdm_cfg.sample_rate;

    size_t ofdm_detected_start = 0;
    float ofdm_detected_snr = 0.0f;
    int ofdm_sync_ok = sync_detect_frame(ofdm_rx_samples, ofdm_rx_len, &sync_cfg_ofdm, &ofdm_detected_start, &ofdm_detected_snr);
    assert(ofdm_sync_ok == 1);
    printf("DEBUG: ofdm_detected_start = %zu, expected = %zu\n", ofdm_detected_start, ofdm_offset);
    assert(labs((long)ofdm_detected_start - (long)ofdm_offset) <= 5);
    printf("PASS: OFDM frame sync detected at correct offset %zu, SNR = %.2f dB\n", ofdm_detected_start, ofdm_detected_snr);

    free(ofdm_sig.data);
    free(ofdm_rx_samples);

    // 5. Silence / Noise-only input timing detection failure
    float* noise_samples = (float*)malloc(10000 * sizeof(float));
    for (int i = 0; i < 10000; i++) {
        noise_samples[i] = ((float)rand() / (float)RAND_MAX - 0.5f) * 0.01f;
    }

    size_t noise_detected_start = 0;
    float noise_detected_snr = 0.0f;
    int noise_sync_ok_css = sync_detect_frame(noise_samples, 10000, &sync_cfg_css, &noise_detected_start, &noise_detected_snr);
    int noise_sync_ok_ofdm = sync_detect_frame(noise_samples, 10000, &sync_cfg_ofdm, &noise_detected_start, &noise_detected_snr);
    assert(noise_sync_ok_css == 0);
    assert(noise_sync_ok_ofdm == 0);
    printf("PASS: Noise-only input correctly rejected (no false alarm detections)\n");

    free(noise_samples);

    printf("All sync tests passed.\n");
    return 0;
}
