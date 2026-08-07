// OFDM demodulator: DFT, channel estimation, equalization, demapping.
// References: MATHEMATICAL_MODEL.md sections 3-4.

#include "soundwave/ofdm.h"
#include "soundwave/chanest.h"
#include "soundwave/equalizer.h"
#include "soundwave/cfo.h"
#include "soundwave/sync.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>

void ofdm_dft_demodulate(const float* y, int N, int cp_length, kiss_fft_cpx* Y) {
    kiss_fft_cpx* temp = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    for (int n = 0; n < N; n++) {
        temp[n].r = y[cp_length + n];
        temp[n].i = 0.0f;
    }
    kiss_fft_cfg fft_cfg = kiss_fft_alloc(N, 0, NULL, NULL); // 0 = forward
    kiss_fft(fft_cfg, temp, Y);
    float norm = 1.0f / sqrtf((float)N);
    for (int n = 0; n < N; n++) {
        Y[n].r *= norm;
        Y[n].i *= norm;
    }
    free(temp);
    free(fft_cfg);
}

uint8_t* ofdm_demodulate(const float* samples, size_t len, sw_config cfg, size_t* out_len) {
    if (!samples || !out_len) {
        if (out_len) *out_len = 0;
        return NULL;
    }

    // Apply defaults to cfg
    if (cfg.sample_rate <= 0) cfg.sample_rate = 44100;
    if (cfg.num_subcarriers <= 0) cfg.num_subcarriers = 256;
    if (cfg.cp_length <= 0) cfg.cp_length = cfg.num_subcarriers / 8;
    if (cfg.num_pilots <= 0) cfg.num_pilots = cfg.num_subcarriers / 16;
    if (cfg.threshold <= 0.0f) cfg.threshold = 3.0f;

    int N = cfg.num_subcarriers;
    int cp = cfg.cp_length;
    float fs = (float)cfg.sample_rate;
    int modulation = (cfg.sf == 1) ? 0 : 1; // 0 = BPSK, 1 = QPSK

    // Subcarrier allocation
    int* data_indices = (int*)malloc(N * sizeof(int));
    int* pilot_indices = (int*)malloc(N * sizeof(int));
    int* null_indices = (int*)malloc(N * sizeof(int));
    int num_data, num_pilots, num_nulls;
    ofdm_allocate_subcarriers(N, data_indices, pilot_indices, null_indices,
                               &num_data, &num_pilots, &num_nulls);

    int N_guard = N / 8;
    int N_active = N / 2 - N_guard - 1;
    int active_start = N_guard + 1;

    // 1. Generate preamble ZC-OFDM frequency-domain template X_pre
    float* zc_real = (float*)malloc(N_active * sizeof(float));
    float* zc_imag = (float*)malloc(N_active * sizeof(float));
    sync_zc_generate(1, N_active, zc_real, zc_imag);

    kiss_fft_cpx* X_pre = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    for (int i = 0; i < N_active; i++) {
        int idx = active_start + i;
        X_pre[idx].r = zc_real[i];
        X_pre[idx].i = zc_imag[i];
    }

    // 2. Modulate preamble symbol to time domain for correlation template
    ofdm_config_t ofdm_cfg;
    ofdm_cfg.num_subcarriers = N;
    ofdm_cfg.cp_length = cp;
    ofdm_cfg.num_pilots = num_pilots;
    ofdm_cfg.pilot_spacing = 8;
    ofdm_cfg.pilot_boost = 1.0f;
    ofdm_cfg.modulation = modulation;

    float* pre_symbol = (float*)malloc((N + cp) * sizeof(float));
    ofdm_modulate_symbol(&ofdm_cfg, X_pre, pre_symbol);

    // 3. Timing synchronization / Preamble detection
    size_t frame_start = 0;
    float detected_snr = 0.0f;
    sync_config_t sync_cfg;
    sync_cfg.mode = 1;
    sync_cfg.threshold = cfg.threshold;
    sync_cfg.zc_root = 1;
    sync_cfg.zc_length = N_active;

    int sync_ok = sync_detect_frame(samples, len, &sync_cfg, &frame_start, &detected_snr);
    if (!sync_ok) {
        // Fallback matched-filter timing detector
        int max_search = (int)len - 2 * (N + cp);
        float max_corr = -1e9f;
        int best_m = -1;
        for (int m = 0; m < max_search; m++) {
            float corr = 0.0f;
            for (int n = 0; n < N + cp; n++) {
                corr += samples[m + n] * pre_symbol[n];
            }
            if (corr > max_corr) {
                max_corr = corr;
                best_m = m;
            }
        }
        if (best_m >= 0) {
            frame_start = (size_t)best_m;
            sync_ok = 1;
        }
    }

    free(pre_symbol);

    if (!sync_ok) {
        free(data_indices); free(pilot_indices); free(null_indices);
        free(zc_real); free(zc_imag); free(X_pre);
        *out_len = 0;
        return NULL;
    }

    // 4. CFO Schmidl-Cox Estimation & Correction
    size_t payload_len = len - frame_start;
    float cfo = sync_schmidl_cox_cfo(samples + frame_start, 2 * (N + cp), N + cp, fs);

    float* analytic_real = (float*)malloc(payload_len * sizeof(float));
    float* analytic_imag = (float*)malloc(payload_len * sizeof(float));
    sync_real_to_analytic(samples + frame_start, payload_len, analytic_real, analytic_imag);

    float* corrected = (float*)malloc(payload_len * sizeof(float));
    sync_apply_cfo_correction(analytic_real, analytic_imag, payload_len, cfo, fs, corrected);

    free(analytic_real);
    free(analytic_imag);

    // 5. Channel Estimation using preamble
    kiss_fft_cpx* Y_pre1 = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* Y_pre2 = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    ofdm_dft_demodulate(corrected, N, cp, Y_pre1);
    ofdm_dft_demodulate(corrected + (N + cp), N, cp, Y_pre2);

    kiss_fft_cpx* Y_pre = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    for (int k = 0; k < N; k++) {
        Y_pre[k].r = 0.5f * (Y_pre1[k].r + Y_pre2[k].r);
        Y_pre[k].i = 0.5f * (Y_pre1[k].i + Y_pre2[k].i);
    }

    // We estimate the channel at active positions (X_pre is known ZC sequence at active positions)
    int* active_indices = (int*)malloc(N_active * sizeof(int));
    kiss_fft_cpx* X_active = (kiss_fft_cpx*)malloc(N_active * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* H_active = (kiss_fft_cpx*)malloc(N_active * sizeof(kiss_fft_cpx));

    for (int i = 0; i < N_active; i++) {
        active_indices[i] = active_start + i;
        X_active[i] = X_pre[active_start + i];
    }

    // Perform Least-Squares (LS) estimation on active positions
    chanest_ls(Y_pre, X_active, active_indices, N_active, H_active);

    // Interpolate channel across all subcarriers (size N)
    kiss_fft_cpx* H = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    chanest_linear_interp(H_active, active_indices, N_active, N, H);

    // Estimate SNR from pilot subcarriers
    // Extract received pilot values Y_p and expected pilot values X_p at pilot indices
    kiss_fft_cpx* Y_p = (kiss_fft_cpx*)malloc(num_pilots * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X_p = (kiss_fft_cpx*)malloc(num_pilots * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* H_p = (kiss_fft_cpx*)malloc(num_pilots * sizeof(kiss_fft_cpx));
    for (int p = 0; p < num_pilots; p++) {
        int idx = pilot_indices[p];
        Y_p[p] = Y_pre[idx];
        X_p[p].r = (p % 2 == 0) ? 1.0f : -1.0f; // BPSK alternating pilots
        X_p[p].i = 0.0f;
        H_p[p] = H[idx];
    }
    float snr_db = chanest_estimate_snr(Y_p, X_p, H_p, num_pilots);
    float inv_snr = 1.0f / powf(10.0f, snr_db / 10.0f);
    if (inv_snr > 10.0f) inv_snr = 10.0f;

    free(Y_p); free(X_p); free(H_p);
    free(Y_pre1); free(Y_pre2); free(Y_pre);
    free(active_indices); free(X_active); free(H_active);

    // 6. Demodulate, Equalize & Demap each data symbol
    int num_symbols = (int)((payload_len - 2 * (N + cp)) / (N + cp));
    if (num_symbols <= 0) {
        free(data_indices); free(pilot_indices); free(null_indices);
        free(zc_real); free(zc_imag); free(X_pre);
        free(corrected); free(H);
        *out_len = 0;
        return NULL;
    }

    int bits_per_symbol = num_data * (modulation == 0 ? 1 : 2);
    int total_allocated_bytes = (num_symbols * bits_per_symbol + 7) / 8;
    uint8_t* decoded = (uint8_t*)calloc(total_allocated_bytes, sizeof(uint8_t));

    kiss_fft_cpx* Y_sym = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X_hat = (kiss_fft_cpx*)malloc(num_data * sizeof(kiss_fft_cpx));
    uint8_t* temp_bits = (uint8_t*)malloc(((bits_per_symbol + 7) / 8) * sizeof(uint8_t));

    size_t total_bits_demodulated = 0;

    for (int s = 0; s < num_symbols; s++) {
        // DFT Demodulation
        float* sym_src = corrected + (2 + s) * (N + cp);
        ofdm_dft_demodulate(sym_src, N, cp, Y_sym);

        // Equalization
        if (cfg.equalizer == 1) {
            equalize_mmse(Y_sym, H, data_indices, num_data, inv_snr, X_hat);
        } else {
            equalize_zf(Y_sym, H, data_indices, num_data, X_hat);
        }

        // Hard Demapping
        size_t bits_decoded = 0;
        demap_data(X_hat, num_data, modulation, temp_bits, &bits_decoded);

        // Append bits to final decoded array
        for (size_t b = 0; b < bits_decoded; b++) {
            int bit_val = (temp_bits[b / 8] >> (7 - (b % 8))) & 1;
            if (total_bits_demodulated % 8 == 0) {
                decoded[total_bits_demodulated / 8] = 0;
            }
            decoded[total_bits_demodulated / 8] |= (bit_val << (7 - (total_bits_demodulated % 8)));
            total_bits_demodulated++;
        }
    }

    free(Y_sym);
    free(X_hat);
    free(temp_bits);
    free(data_indices);
    free(pilot_indices);
    free(null_indices);
    free(zc_real);
    free(zc_imag);
    free(X_pre);
    free(corrected);
    free(H);

    *out_len = total_bits_demodulated;
    return decoded;
}

uint8_t* ofdm_demodulate_frame(const float* samples, size_t len,
                                const ofdm_config_t* cfg, size_t* out_len) {
    if (!samples || !cfg || !out_len) {
        if (out_len) *out_len = 0;
        return NULL;
    }
    sw_config_t sw_cfg;
    sw_cfg.sample_rate = 44100;
    sw_cfg.num_subcarriers = cfg->num_subcarriers;
    sw_cfg.cp_length = cfg->cp_length;
    sw_cfg.num_pilots = cfg->num_pilots;
    sw_cfg.sf = (cfg->modulation == 0) ? 1 : 8; // 1 = BPSK, 8 = QPSK
    sw_cfg.equalizer = 0;
    sw_cfg.threshold = 3.0f;

    size_t out_bits = 0;
    uint8_t* decoded = ofdm_demodulate(samples, len, sw_cfg, &out_bits);
    *out_len = (out_bits + 7) / 8; // return byte count
    return decoded;
}
