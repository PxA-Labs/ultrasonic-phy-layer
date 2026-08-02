// CSS modulator: generates upchirps and frequency-shifts them per symbol value.
// References: MATHEMATICAL_MODEL.md section 2.1.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

void css_init(css_config_t* cfg) {
    cfg->chirp_len = (int)(cfg->sample_rate * (float)(1 << cfg->sf) / cfg->bandwidth);
}

void css_generate_upchirp_raw(const css_config_t* cfg, float* chirp) {
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

void css_modulate_symbol_raw(const css_config_t* cfg, int sym_value, float* symbol) {
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

// Issue 19 functions
sw_signal css_generate_chirp(double f0, double B, double T, double A, double phi0, double fs) {
    sw_signal sig;
    int N = (int)(T * fs + 0.5);
    sig.data = (float*)malloc(N * sizeof(float));
    sig.length = N;
    sig.sample_rate = (float)fs;
    if (!sig.data) return sig;

    for (int n = 0; n < N; n++) {
        double t = (double)n / fs;
        double phase = SW_TWO_PI * (f0 + (B / (2.0 * T)) * t) * t + phi0;
        sig.data[n] = (float)(A * cos(phase));
    }
    return sig;
}

sw_signal css_generate_upchirp(sw_config cfg) {
    return css_generate_chirp(cfg.carrier_freq, +cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
}

sw_signal css_generate_downchirp(sw_config cfg) {
    return css_generate_chirp(cfg.carrier_freq, -cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
}

sw_signal css_modulate_symbol(int bit, sw_config cfg) {
    if (bit == 0) {
        return css_generate_upchirp(cfg);
    } else {
        return css_generate_downchirp(cfg);
    }
}

sw_signal css_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg) {
    sw_signal final_sig;
    final_sig.data = NULL;
    final_sig.length = 0;
    final_sig.sample_rate = (float)cfg.sample_rate;

    // 1. Generate preamble (8 upchirps, 2 downchirps using cfg parameters)
    sw_signal pre_up = css_generate_chirp(cfg.carrier_freq, cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
    sw_signal pre_down = css_generate_chirp(cfg.carrier_freq, -cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);

    int N_pre = pre_up.length;
    int N_sym = (int)(cfg.symbol_duration * cfg.sample_rate + 0.5f);

    size_t total_samples = 8 * N_pre + 2 * N_pre + num_bits * N_sym;
    final_sig.data = (float*)malloc(total_samples * sizeof(float));
    if (!final_sig.data) {
        free(pre_up.data);
        free(pre_down.data);
        return final_sig;
    }
    final_sig.length = total_samples;

    size_t offset = 0;
    // 8 up-chirps
    for (int i = 0; i < 8; i++) {
        memcpy(final_sig.data + offset, pre_up.data, N_pre * sizeof(float));
        offset += N_pre;
    }
    // 2 down-chirps
    for (int i = 0; i < 2; i++) {
        memcpy(final_sig.data + offset, pre_down.data, N_pre * sizeof(float));
        offset += N_pre;
    }

    free(pre_up.data);
    free(pre_down.data);

    // 2. Modulate each bit
    for (size_t i = 0; i < num_bits; i++) {
        int bit_val = (bits[i / 8] >> (7 - (i % 8))) & 1;
        sw_signal sym = css_modulate_symbol(bit_val, cfg);
        if (sym.data) {
            memcpy(final_sig.data + offset, sym.data, N_sym * sizeof(float));
            free(sym.data);
        }
        offset += N_sym;
    }

    return final_sig;
}
