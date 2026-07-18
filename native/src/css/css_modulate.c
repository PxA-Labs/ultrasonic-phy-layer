// CSS modulator: generates upchirps and frequency-shifts them per symbol value.
// References: MATHEMATICAL_MODEL.md section 2.1.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>

void css_init(css_config_t* cfg) {
    cfg->chirp_len = (int)(cfg->sample_rate * (float)(1 << cfg->sf) / cfg->bandwidth);
}

void css_generate_upchirp(const css_config_t* cfg, float* chirp) {
    int N = cfg->chirp_len;
    float fs = cfg->sample_rate;
    float f0 = cfg->f0;
    float mu = cfg->bandwidth / ((float)N / fs);
    for (int n = 0; n < N; n++) {
        float t = (float)n / fs;
        float phase = SW_TWO_PI * (f0 * t + 0.5f * mu * t * t);
        chirp[n] = cosf(phase);
    }
}

void css_modulate_symbol(const css_config_t* cfg, int sym_value, float* symbol) {
    int N = cfg->chirp_len;
    float fs = cfg->sample_rate;
    float f0 = cfg->f0;
    float mu = cfg->bandwidth / ((float)N / fs);
    float df = (float)sym_value / (float)(1 << cfg->sf) * cfg->bandwidth;
    for (int n = 0; n < N; n++) {
        float t = (float)n / fs;
        float phase = SW_TWO_PI * ((f0 + df) * t + 0.5f * mu * t * t);
        symbol[n] = cosf(phase);
    }
}

void css_modulate(const css_config_t* cfg, const uint8_t* bits,
                  size_t bit_len, float* samples, size_t* sample_len) {
    (void)bits; (void)bit_len; (void)samples;
    *sample_len = 0; // TODO
}

void css_generate_preamble(const css_config_t* cfg, int num_chirps, float* preamble) {
    for (int i = 0; i < num_chirps; i++)
        css_generate_upchirp(cfg, preamble + i * cfg->chirp_len);
}
