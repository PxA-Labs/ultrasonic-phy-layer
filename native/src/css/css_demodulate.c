// CSS demodulator: dechirp + FFT peak detection for symbol extraction.
// References: MATHEMATICAL_MODEL.md section 2.2.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include "kiss_fft.h"
#include <string.h>
#include <math.h>

void css_generate_downchirp(const css_config_t* cfg, float* downchirp) {
    int N = cfg->chirp_len;
    float fs = cfg->sample_rate;
    float f0 = cfg->f0;
    float mu = cfg->bandwidth / ((float)N / fs);
    for (int n = 0; n < N; n++) {
        float t = (float)n / fs;
        float phase = -SW_TWO_PI * (f0 * t + 0.5f * mu * t * t);
        downchirp[n] = cosf(phase);
    }
}

void css_dechirp(const float* samples, int N, const float* downchirp,
                 float* dechirped, int N_fft) {
    for (int n = 0; n < N; n++)
        dechirped[n] = samples[n] * downchirp[n];
    for (int n = N; n < N_fft; n++)
        dechirped[n] = 0.0f;
}

int css_extract_symbol(const float* samples, int N,
                       const float* downchirp, int N_fft, int SF) {
    (void)samples; (void)N; (void)downchirp; (void)N_fft; (void)SF;
    return 0; // TODO
}

uint8_t* css_demodulate_frame(const float* samples, size_t len,
                               const css_config_t* cfg, size_t* out_bytes) {
    (void)samples; (void)len; (void)cfg;
    *out_bytes = 0;
    return NULL; // TODO
}
