// OFDM modulator: constellation mapping, pilot insertion, IDFT, cyclic prefix.
// References: MATHEMATICAL_MODEL.md section 2.3.

#include "soundwave/ofdm.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>

void ofdm_init(ofdm_config_t* cfg) {
    (void)cfg;
}

void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X) {
    (void)cfg; (void)bits; (void)bit_len; (void)X;
}

void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X) {
    (void)cfg; (void)X;
}

void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time) {
    int N = cfg->num_subcarriers;
    int cp = cfg->cp_length;
    kiss_fft_cpx* freq = (kiss_fft_cpx*)X;  // alias
    kiss_fft_cfg fft_cfg = kiss_fft_alloc(N, 1, NULL, NULL); // 1 = inverse
    kiss_fft_cpx* temp = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft(fft_cfg, freq, temp);
    // Copy with CP
    for (int n = 0; n < N; n++)
        time[cp + n] = temp[n].r / (float)N;
    for (int n = 0; n < cp; n++)
        time[n] = time[N + n];
    free(temp);
    free(fft_cfg);
}

void ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len) {
    (void)cfg; (void)bits; (void)bit_len; (void)samples;
    *sample_len = 0; // TODO
}
