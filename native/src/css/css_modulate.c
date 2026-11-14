// CSS modulator: generates upchirps and frequency-shifts them per symbol value.
// References: MATHEMATICAL_MODEL.md section 2.1.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include <string.h>
#include <stdint.h>
#include <math.h>

#define CSS_PREAMBLE_UP       8
#define CSS_PREAMBLE_DOWN     2
#define CSS_MAX_CHIRP_SAMPLES (1 << 20)
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
    sig.data = NULL;
    sig.length = 0;
    sig.sample_rate = (float)fs;
    // Reject inputs whose sample count is non-finite, empty or absurdly large
    // before converting to int (float->int overflow is UB).
    double count = T * fs + 0.5;
    if (!isfinite(count) || count < 1.0 || count > (double)CSS_MAX_CHIRP_SAMPLES) return sig;
    int N = (int)count;
    sig.data = (float*)malloc((size_t)N * sizeof(float));
    if (!sig.data) return sig;
    sig.length = (size_t)N;

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

sw_signal css_generate_downchirp_signal(sw_config cfg) {
    return css_generate_chirp(cfg.carrier_freq, -cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
}

sw_signal css_modulate_symbol(int bit, sw_config cfg) {
    if (bit == 0) {
        return css_generate_upchirp(cfg);
    } else {
        return css_generate_downchirp_signal(cfg);
    }
}

sw_signal css_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg) {
    sw_signal final_sig;
    final_sig.data = NULL;
    final_sig.length = 0;
    final_sig.sample_rate = 0.0f;
    if (!bits || num_bits == 0) return final_sig;

    // Apply defaults to cfg
    if (cfg.sample_rate <= 0) cfg.sample_rate = 44100;
    if (cfg.sf <= 0) cfg.sf = 8;
    if (cfg.carrier_freq <= 0.0f) cfg.carrier_freq = 19000.0f;
    if (cfg.bandwidth <= 0.0f) cfg.bandwidth = 2000.0f;
    if (cfg.symbol_duration <= 0.0f) cfg.symbol_duration = 0.02f;
    if (cfg.amplitude <= 0.0f) cfg.amplitude = 0.8f;
    final_sig.sample_rate = (float)cfg.sample_rate;

    // A data symbol is exactly an up-chirp (bit 0) or a down-chirp (bit 1)
    // with the preamble's parameters, so both templates are generated once and
    // their length is the single source of truth for the symbol length. (The
    // symbol length used to be recomputed in float precision, which could
    // differ by one sample from the template and over-read it on every bit.)
    sw_signal up = css_generate_chirp(cfg.carrier_freq, cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
    sw_signal down = css_generate_chirp(cfg.carrier_freq, -cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
    if (!up.data || !down.data || up.length != down.length) goto done;

    size_t n_sym = up.length;
    size_t preamble = CSS_PREAMBLE_UP + CSS_PREAMBLE_DOWN;
    if (num_bits > (SIZE_MAX / sizeof(float)) / n_sym - preamble) goto done; // overflow
    size_t total_samples = (preamble + num_bits) * n_sym;

    final_sig.data = (float*)malloc(total_samples * sizeof(float));
    if (!final_sig.data) goto done;
    final_sig.length = total_samples;

    float* out = final_sig.data;
    for (int i = 0; i < CSS_PREAMBLE_UP; i++, out += n_sym)
        memcpy(out, up.data, n_sym * sizeof(float));
    for (int i = 0; i < CSS_PREAMBLE_DOWN; i++, out += n_sym)
        memcpy(out, down.data, n_sym * sizeof(float));
    for (size_t i = 0; i < num_bits; i++, out += n_sym) {
        int bit_val = (bits[i / 8] >> (7 - (i % 8))) & 1;
        memcpy(out, bit_val ? down.data : up.data, n_sym * sizeof(float));
    }

done:
    free(up.data);
    free(down.data);
    return final_sig;
}
