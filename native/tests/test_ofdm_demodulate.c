// Unit tests for OFDM demodulation, channel estimation, and equalization.
// References: MATHEMATICAL_MODEL.md section 4.

#include "soundwave/ofdm.h"
#include "soundwave/chanest.h"
#include "soundwave/equalizer.h"
#include "soundwave/common.h"
#include "kiss_fft.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <math.h>

int main(void) {
    printf("Running test_ofdm_demodulate...\n");

    int N = 64;
    int cp = 16;
    int num_data = 20;

    ofdm_config_t cfg = {
        .num_subcarriers = N,
        .cp_length = cp,
        .modulation = 1, // QPSK
        .num_pilots = 8,
        .pilot_boost = 1.0f,
        .pilot_spacing = 8,
    };
    ofdm_init(&cfg);

    // Indices definitions
    int* data_indices = (int*)malloc(N * sizeof(int));
    int* pilot_indices = (int*)malloc(N * sizeof(int));
    int* null_indices = (int*)malloc(N * sizeof(int));
    int n_data, n_pilots, n_nulls;
    ofdm_allocate_subcarriers(N, data_indices, pilot_indices, null_indices, &n_data, &n_pilots, &n_nulls);
    assert(n_data == num_data);

    // --- Test 1: Flat Channel H=[1,1,...1] ZF Equalizer -> identity ---
    kiss_fft_cpx* Y_flat = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* H_flat = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X_hat = (kiss_fft_cpx*)malloc(num_data * sizeof(kiss_fft_cpx));

    for (int k = 0; k < N; k++) {
        Y_flat[k].r = (float)k;
        Y_flat[k].i = 0.0f;
        H_flat[k].r = 1.0f;
        H_flat[k].i = 0.0f;
    }

    equalize_zf(Y_flat, H_flat, data_indices, num_data, X_hat);

    for (int i = 0; i < num_data; i++) {
        int k = data_indices[i];
        assert(fabsf(X_hat[i].r - Y_flat[k].r) <= 1e-6f);
        assert(fabsf(X_hat[i].i - Y_flat[k].i) <= 1e-6f);
    }
    printf("PASS: Flat channel ZF Equalizer identity verified.\n");

    // --- Test 2: Known Channel Recovery ---
    // Apply channel H to known symbols X, verify LS estimation at pilots
    kiss_fft_cpx* X_p = (kiss_fft_cpx*)malloc(n_pilots * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* H_p_expected = (kiss_fft_cpx*)malloc(n_pilots * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* H_p_est = (kiss_fft_cpx*)malloc(n_pilots * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* Y_p = (kiss_fft_cpx*)malloc(n_pilots * sizeof(kiss_fft_cpx));

    for (int p = 0; p < n_pilots; p++) {
        X_p[p].r = (p % 2 == 0) ? 1.0f : -1.0f;
        X_p[p].i = 0.0f;
        H_p_expected[p].r = 0.8f + 0.1f * p;
        H_p_expected[p].i = -0.2f + 0.05f * p;

        // Y = H * X
        Y_p[p].r = H_p_expected[p].r * X_p[p].r - H_p_expected[p].i * X_p[p].i;
        Y_p[p].i = H_p_expected[p].r * X_p[p].i + H_p_expected[p].i * X_p[p].r;
    }

    // Since chanest_ls maps Y[pilot_indices[i]] directly, let's create a full Y spectrum
    kiss_fft_cpx* Y_full = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    for (int p = 0; p < n_pilots; p++) {
        Y_full[pilot_indices[p]] = Y_p[p];
    }

    chanest_ls(Y_full, X_p, pilot_indices, n_pilots, H_p_est);

    for (int p = 0; p < n_pilots; p++) {
        assert(fabsf(H_p_est[p].r - H_p_expected[p].r) <= 1e-6f);
        assert(fabsf(H_p_est[p].i - H_p_expected[p].i) <= 1e-6f);
    }
    printf("PASS: Known channel LS estimation verified.\n");

    // --- Test 3: MMSE vs ZF comparison at SNR = 0 dB and 20 dB ---
    float inv_snr_0db = 1.0f;     // 10^(0/10) = 1.0
    float inv_snr_20db = 0.01f;   // 10^(-20/10) = 0.01

    kiss_fft_cpx* X_hat_zf = (kiss_fft_cpx*)malloc(num_data * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X_hat_mmse = (kiss_fft_cpx*)malloc(num_data * sizeof(kiss_fft_cpx));

    // Simulate deep fade on a subcarrier (H near 0)
    kiss_fft_cpx* H_fade = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    for (int k = 0; k < N; k++) {
        H_fade[k].r = 0.01f; // Fade
        H_fade[k].i = 0.01f;
    }

    Y_full[data_indices[0]].r = 1.0f;
    Y_full[data_indices[0]].i = 1.0f;

    equalize_zf(Y_full, H_fade, data_indices, num_data, X_hat_zf);
    equalize_mmse(Y_full, H_fade, data_indices, num_data, inv_snr_0db, X_hat_mmse);

    // ZF should amplify noise (large values) whereas MMSE is regularized
    // Let's assert MMSE magnitude is much smaller than ZF (i.e. regularized)
    float mag2_zf = X_hat_zf[0].r * X_hat_zf[0].r + X_hat_zf[0].i * X_hat_zf[0].i;
    float mag2_mmse = X_hat_mmse[0].r * X_hat_mmse[0].r + X_hat_mmse[0].i * X_hat_mmse[0].i;
    assert(mag2_mmse < mag2_zf);

    // At 20 dB SNR on flat channel, MMSE should be very close to ZF
    equalize_mmse(Y_full, H_flat, data_indices, num_data, inv_snr_20db, X_hat_mmse);
    float mag2_mmse_20db = X_hat_mmse[0].r * X_hat_mmse[0].r + X_hat_mmse[0].i * X_hat_mmse[0].i;
    // ZF on flat channel
    equalize_zf(Y_full, H_flat, data_indices, num_data, X_hat_zf);
    float mag2_zf_flat = X_hat_zf[0].r * X_hat_zf[0].r + X_hat_zf[0].i * X_hat_zf[0].i;
    assert(fabsf(mag2_mmse_20db - mag2_zf_flat) / mag2_zf_flat < 0.2f);
    printf("PASS: MMSE vs ZF noise regularization compared successfully.\n");

    // --- Test 4: Modulate -> Demodulate own modulated signal (100% recovery) ---
    sw_config_t sw_cfg;
    sw_cfg.sample_rate = 44100;
    sw_cfg.num_subcarriers = 256;
    sw_cfg.cp_length = 32;
    sw_cfg.num_pilots = 16;
    sw_cfg.equalizer = 0; // ZF
    sw_cfg.sf = 8; // QPSK
    sw_cfg.threshold = 3.0f;

    uint8_t payload[16] = { 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
                            0x0D, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE };

    // Modulate
    sw_signal tx_sig = ofdm_modulate(payload, 16 * 8, sw_cfg);
    assert(tx_sig.data != NULL);

    // Demodulate
    size_t rx_bits = 0;
    uint8_t* rx_payload = ofdm_demodulate(tx_sig.data, tx_sig.length, sw_cfg, &rx_bits);
    assert(rx_payload != NULL);
    assert(rx_bits >= 16 * 8);

    // Compare
    if (memcmp(payload, rx_payload, 16) != 0) {
        printf("MISMATCH:\nTX: ");
        for (int i = 0; i < 16; i++) printf("%02X ", payload[i]);
        printf("\nRX: ");
        for (int i = 0; i < 16; i++) printf("%02X ", rx_payload[i]);
        printf("\n");
    }
    assert(memcmp(payload, rx_payload, 16) == 0);
    printf("PASS: Modulate -> Demodulate loopback returned 100%% matching bits.\n");

    // Clean up
    free(data_indices); free(pilot_indices); free(null_indices);
    free(Y_flat); free(H_flat); free(X_hat);
    free(X_p); free(H_p_expected); free(H_p_est); free(Y_p); free(Y_full);
    free(X_hat_zf); free(X_hat_mmse); free(H_fade);
    free(tx_sig.data); free(rx_payload);

    printf("All OFDM demodulate tests passed successfully!\n");
    return 0;
}
