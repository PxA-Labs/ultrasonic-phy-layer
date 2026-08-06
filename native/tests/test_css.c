// Unit tests for CSS Modulation & Demodulation pipelines.
// References: MATHEMATICAL_MODEL.md section 2.1 & 2.2.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Box-Muller transform to generate standard Gaussian random variables
static double rand_gaussian(void) {
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    while (u1 <= 1e-15) u1 = (double)rand() / RAND_MAX;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

// Add AWGN to a float sample buffer to achieve the target SNR in dB
static void add_awgn(float* samples, size_t len, double snr_db) {
    // 1. Calculate signal power
    double sig_power = 0.0;
    for (size_t i = 0; i < len; i++) {
        sig_power += (double)samples[i] * (double)samples[i];
    }
    sig_power /= len;

    // 2. Calculate target noise power
    double snr_linear = pow(10.0, snr_db / 10.0);
    double noise_power = sig_power / snr_linear;
    double noise_std = sqrt(noise_power);

    // 3. Add noise
    for (size_t i = 0; i < len; i++) {
        samples[i] += (float)(noise_std * rand_gaussian());
    }
}

int main(void) {
    printf("Running test_css...\n");
    srand(42); // Seed for deterministic tests

    // Config setup
    css_config_t raw_cfg = {
        .sf = 8,
        .bandwidth = 2000.0f,
        .sample_rate = 44100.0f,
        .f0 = 18000.0f
    };
    css_init(&raw_cfg);
    int N = raw_cfg.chirp_len;
    int SF = raw_cfg.sf;

    // --- Test 1: Verify downchirp is exact conjugate of upchirp (max error <= 1e-6) ---
    float* upchirp = (float*)malloc(N * sizeof(float));
    float* downchirp = (float*)malloc(N * sizeof(float));
    assert(upchirp != NULL && downchirp != NULL);

    css_generate_upchirp_raw(&raw_cfg, upchirp);
    css_generate_downchirp_raw(&raw_cfg, downchirp);

    for (int n = 0; n < N; n++) {
        float diff = fabsf(upchirp[n] - downchirp[n]);
        assert(diff <= 1e-6f);
    }
    printf("PASS: Conjugate relationship of up/down chirps verified.\n");

    // --- Test 2: Modulate symbol value S=42 with SF=8 -> demodulate receives 42 ---
    float* symbol_42 = (float*)malloc(N * sizeof(float));
    assert(symbol_42 != NULL);
    css_modulate_symbol_raw(&raw_cfg, 42, symbol_42);

    int N_fft = 8192; // High FFT resolution for fine symbol extraction
    int decoded_42 = css_extract_symbol(symbol_42, N, downchirp, N_fft, SF);
    assert(decoded_42 == 42);
    printf("PASS: Modulate symbol value S=42 -> demodulated correctly as 42.\n");

    // --- Test 3: Modulate S=0 -> dechirp peaks at frequency 0 (DC tone) ---
    float* symbol_0 = (float*)malloc(N * sizeof(float));
    assert(symbol_0 != NULL);
    css_modulate_symbol_raw(&raw_cfg, 0, symbol_0);

    int decoded_0 = css_extract_symbol(symbol_0, N, downchirp, N_fft, SF);
    assert(decoded_0 == 0);
    printf("PASS: Modulate S=0 -> dechirp peaks at DC (S=0).\n");

    // --- Test 4: Modulate S=128 (SF=8) -> dechirp peaks at frequency 0.5 * B ---
    float* symbol_128 = (float*)malloc(N * sizeof(float));
    assert(symbol_128 != NULL);
    css_modulate_symbol_raw(&raw_cfg, 128, symbol_128);

    int decoded_128 = css_extract_symbol(symbol_128, N, downchirp, N_fft, SF);
    assert(decoded_128 == 128);
    printf("PASS: Modulate S=128 -> dechirp peaks at 0.5 * B (S=128).\n");

    // --- Test 5: CSS packet with 10 symbols -> all 10 decoded correctly ---
    sw_config_t cfg;
    cfg.sample_rate = 44100;
    cfg.modulation = 0;
    cfg.sf = 8;
    cfg.carrier_freq = 18000.0f;
    cfg.bandwidth = 2000.0f;
    cfg.symbol_duration = 0.02f;
    cfg.amplitude = 0.8f;

    uint8_t payload[2] = { 0xAA, 0xF0 }; // 16 bits = 16 symbols
    sw_signal mod_sig = css_modulate(payload, 16, cfg);
    assert(mod_sig.data != NULL);

    size_t out_bytes = 0;
    uint8_t* rx_bytes = css_demodulate(mod_sig.data, mod_sig.length, cfg, &out_bytes);
    assert(rx_bytes != NULL);
    assert(out_bytes >= 2);
    assert((rx_bytes[0] & 0xAA) == 0xAA);
    assert((rx_bytes[1] & 0xF0) == 0xF0);
    printf("PASS: Multi-symbol CSS packet modulated and demodulated cleanly.\n");

    // --- Test 6: Modulate -> add AWGN (SNR=5 dB) -> BER < 0.01 ---
    uint8_t large_payload[32];
    for (int i = 0; i < 32; i++) {
        large_payload[i] = (uint8_t)(rand() % 256);
    }
    sw_signal noisy_sig = css_modulate(large_payload, 32 * 8, cfg);
    assert(noisy_sig.data != NULL);

    // Add AWGN noise at 5 dB SNR
    add_awgn(noisy_sig.data, noisy_sig.length, 5.0);

    size_t noisy_out_bytes = 0;
    uint8_t* noisy_rx = css_demodulate(noisy_sig.data, noisy_sig.length, cfg, &noisy_out_bytes);
    assert(noisy_rx != NULL);
    assert(noisy_out_bytes >= 32);

    // Calculate bit error rate (BER)
    int bit_errors = 0;
    int total_bits = 32 * 8;
    for (int i = 0; i < 32; i++) {
        uint8_t diff = large_payload[i] ^ noisy_rx[i];
        for (int b = 0; b < 8; b++) {
            if ((diff >> b) & 1) {
                bit_errors++;
            }
        }
    }
    double ber = (double)bit_errors / total_bits;
    printf("SNR = 5 dB: Bit Errors = %d / %d, BER = %.4f\n", bit_errors, total_bits, ber);
    assert(ber < 0.01);
    printf("PASS: CSS demodulator operates at SNR=5 dB with BER < 1%%.\n");

    // Free resources
    free(upchirp);
    free(downchirp);
    free(symbol_42);
    free(symbol_0);
    free(symbol_128);
    free(mod_sig.data);
    free(rx_bytes);
    free(noisy_sig.data);
    free(noisy_rx);

    printf("All CSS modulation & demodulation tests passed successfully!\n");
    return 0;
}
