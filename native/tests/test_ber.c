#include "soundwave/soundwave.h"
#include "awgn_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

int count_bit_errors(const uint8_t* tx, const uint8_t* rx, size_t num_bytes) {
    int errors = 0;
    for (size_t i = 0; i < num_bytes; i++) {
        uint8_t diff = tx[i] ^ rx[i];
        while (diff) {
            if (diff & 1) errors++;
            diff >>= 1;
        }
    }
    return errors;
}

int main(void) {
    printf("Running BER/FER benchmarking harness under AWGN...\n");

    // CSV header
    printf("Mode,SNR_dB,Tx_Bits,Err_Bits,BER,FER\n");

    uint8_t payload[8] = { 0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89 };
    size_t payload_bits = 8 * 8;

    float snr_sweep[] = { -5.0f, 0.0f, 3.0f, 5.0f, 10.0f, 15.0f, 20.0f };
    int num_steps = sizeof(snr_sweep) / sizeof(snr_sweep[0]);

    // 1. CSS Mode Sweep
    sw_config_t css_cfg;
    memset(&css_cfg, 0, sizeof(css_cfg));
    css_cfg.sample_rate = 44100;
    css_cfg.sf = 8;
    css_cfg.carrier_freq = 19000.0f;
    css_cfg.bandwidth = 2000.0f;
    css_cfg.symbol_duration = 0.02f;
    css_cfg.amplitude = 0.8f;

    for (int step = 0; step < num_steps; step++) {
        float snr = snr_sweep[step];
        int total_bits = 0;
        int total_errors = 0;
        int frame_errors = 0;
        int num_frames = 20;

        for (int f = 0; f < num_frames; f++) {
            // Modulate
            float* samples = (float*)malloc(1000000 * sizeof(float));
            size_t sample_len = 1000000;
            int ret = sw_css_modulate(payload, payload_bits, css_cfg, samples, &sample_len);
            assert(ret == SW_OK);

            // Add trailing padding to prevent synchronization offset truncation
            size_t pad_len = 1000;
            memset(samples + sample_len, 0, pad_len * sizeof(float));
            sample_len += pad_len;

            // Add noise
            float* noisy = (float*)malloc(sample_len * sizeof(float));
            awgn_add_noise(samples, sample_len, snr, noisy);

            // Demodulate
            uint8_t rx_buf[256];
            memset(rx_buf, 0, sizeof(rx_buf));
            size_t rx_bits = 2000;
            ret = sw_css_demodulate(noisy, sample_len, css_cfg, rx_buf, &rx_bits);

            int errs = 0;
            if (ret != SW_OK) {
                errs = (int)payload_bits;
                frame_errors++;
            } else {
                errs = count_bit_errors(payload, rx_buf, 8);
                if (errs > 0) frame_errors++;
            }

            total_bits += (int)payload_bits;
            total_errors += errs;

            free(samples);
            free(noisy);
        }

        double ber = (double)total_errors / (double)total_bits;
        double fer = (double)frame_errors / (double)num_frames;
        printf("CSS,%.1f,%d,%d,%e,%.2f\n", snr, total_bits, total_errors, ber, fer);

        // Assert threshold: CSS mode must achieve BER < 10^-3 at SNR >= 3 dB
        if (snr >= 3.0f) {
            assert(ber < 1e-3);
        }
    }

    // 2. OFDM Mode Sweep
    sw_config_t ofdm_cfg;
    memset(&ofdm_cfg, 0, sizeof(ofdm_cfg));
    ofdm_cfg.sample_rate = 44100;
    ofdm_cfg.num_subcarriers = 256;
    ofdm_cfg.cp_length = 32;
    ofdm_cfg.num_pilots = 16;
    ofdm_cfg.ofdm_modulation = 1; // QPSK
    ofdm_cfg.threshold = 3.0f;

    for (int step = 0; step < num_steps; step++) {
        float snr = snr_sweep[step];
        int total_bits = 0;
        int total_errors = 0;
        int frame_errors = 0;
        int num_frames = 20;

        for (int f = 0; f < num_frames; f++) {
            // Modulate
            float* samples = (float*)malloc(1000000 * sizeof(float));
            size_t sample_len = 1000000;
            int ret = sw_ofdm_modulate(payload, payload_bits, ofdm_cfg, samples, &sample_len);
            assert(ret == SW_OK);

            // Add trailing padding to prevent synchronization offset truncation
            size_t pad_len = 1000;
            memset(samples + sample_len, 0, pad_len * sizeof(float));
            sample_len += pad_len;

            // Add noise
            float* noisy = (float*)malloc(sample_len * sizeof(float));
            awgn_add_noise(samples, sample_len, snr, noisy);

            // Demodulate
            uint8_t rx_buf[256];
            memset(rx_buf, 0, sizeof(rx_buf));
            size_t rx_bits = 2000;
            ret = sw_ofdm_demodulate(noisy, sample_len, ofdm_cfg, rx_buf, &rx_bits);

            int errs = 0;
            if (ret != SW_OK) {
                errs = (int)payload_bits;
                frame_errors++;
            } else {
                errs = count_bit_errors(payload, rx_buf, 8);
                if (errs > 0) frame_errors++;
            }

            total_bits += (int)payload_bits;
            total_errors += errs;

            free(samples);
            free(noisy);
        }

        double ber = (double)total_errors / (double)total_bits;
        double fer = (double)frame_errors / (double)num_frames;
        printf("OFDM,%.1f,%d,%d,%e,%.2f\n", snr, total_bits, total_errors, ber, fer);

        // Assert threshold: OFDM mode should also perform well at high SNR
        if (snr >= 10.0f) {
            assert(ber < 1e-2);
        }
    }

    printf("All BER benchmarks passed successfully.\n");
    return 0;
}
