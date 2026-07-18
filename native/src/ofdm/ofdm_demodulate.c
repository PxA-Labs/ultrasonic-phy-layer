// OFDM demodulator: DFT, channel estimation, equalization, demapping.
// References: MATHEMATICAL_MODEL.md sections 3-4.

#include "soundwave/ofdm.h"
#include "soundwave/chanest.h"
#include "soundwave/equalizer.h"
#include "soundwave/common.h"
#include <string.h>

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

uint8_t* ofdm_demodulate_frame(const float* samples, size_t len,
                                const ofdm_config_t* cfg, size_t* out_len) {
    (void)samples; (void)len; (void)cfg;
    *out_len = 0;
    return NULL; // TODO
}
