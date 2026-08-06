// CSS demodulator: dechirp + FFT peak detection for symbol extraction.
// References: MATHEMATICAL_MODEL.md section 2.2.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include "kiss_fft.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

void css_generate_downchirp_raw(const css_config_t* cfg, float* downchirp) {
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
    if (N_fft <= 0 || SF <= 0 || N <= 0) return 0;

    // Allocate KissFFT complex arrays
    kiss_fft_cpx* fft_in = (kiss_fft_cpx*)malloc(N_fft * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* fft_out = (kiss_fft_cpx*)malloc(N_fft * sizeof(kiss_fft_cpx));
    if (!fft_in || !fft_out) {
        free(fft_in);
        free(fft_out);
        return 0;
    }

    // Multiply by downchirp (dechirp) and zero-pad
    for (int n = 0; n < N; n++) {
        fft_in[n].r = samples[n] * downchirp[n];
        fft_in[n].i = 0.0f;
    }
    for (int n = N; n < N_fft; n++) {
        fft_in[n].r = 0.0f;
        fft_in[n].i = 0.0f;
    }

    // Run Forward FFT (0 = forward)
    kiss_fft_cfg cfg = kiss_fft_alloc(N_fft, 0, NULL, NULL);
    if (!cfg) {
        free(fft_in);
        free(fft_out);
        return 0;
    }
    kiss_fft(cfg, fft_in, fft_out);

    // Compute power spectrum and find peak in [0, N_fft / 2]
    float max_power = -1.0f;
    int k_peak = 0;
    int search_limit = N_fft / 2;

    for (int k = 0; k <= search_limit; k++) {
        float power = fft_out[k].r * fft_out[k].r + fft_out[k].i * fft_out[k].i;
        if (power > max_power) {
            max_power = power;
            k_peak = k;
        }
    }

    // Map peak bin back to symbol value:
    // sym_value = round( k_peak * N / N_fft )
    double ratio = (double)k_peak * (double)N / (double)N_fft;
    int sym_value = (int)(ratio + 0.5);

    // Wrap symbol value
    sym_value = (sym_value + (1 << SF)) % (1 << SF);

    free(fft_in);
    free(fft_out);
    free(cfg);

    return sym_value;
}

uint8_t* css_demodulate(const float* samples, size_t len, sw_config cfg, size_t* out_bytes) {
    if (!samples || !out_bytes) {
        if (out_bytes) *out_bytes = 0;
        return NULL;
    }

    // Apply defaults to cfg
    if (cfg.sample_rate <= 0) cfg.sample_rate = 44100;
    if (cfg.sf <= 0) cfg.sf = 8;
    if (cfg.carrier_freq <= 0.0f) cfg.carrier_freq = 19000.0f;
    if (cfg.bandwidth <= 0.0f) cfg.bandwidth = 2000.0f;
    if (cfg.symbol_duration <= 0.0f) cfg.symbol_duration = 0.02f;
    if (cfg.amplitude <= 0.0f) cfg.amplitude = 0.8f;

    int N_pre = (int)(cfg.symbol_duration * cfg.sample_rate + 0.5);
    int N_sym = N_pre;

    // Generate templates
    sw_signal pre_up = css_generate_chirp(cfg.carrier_freq, cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);
    sw_signal pre_down = css_generate_chirp(cfg.carrier_freq, -cfg.bandwidth, cfg.symbol_duration, cfg.amplitude, 0.0, cfg.sample_rate);

    if (!pre_up.data || !pre_down.data) {
        free(pre_up.data);
        free(pre_down.data);
        *out_bytes = 0;
        return NULL;
    }

    // Sync
    int max_search = (int)len - 10 * N_pre;
    if (max_search <= 0) {
        free(pre_up.data);
        free(pre_down.data);
        *out_bytes = 0;
        return NULL;
    }

    float* power_up = (float*)calloc(max_search, sizeof(float));
    float* power_down = (float*)calloc(max_search, sizeof(float));
    if (!power_up || !power_down) {
        free(pre_up.data);
        free(pre_down.data);
        free(power_up);
        free(power_down);
        *out_bytes = 0;
        return NULL;
    }

    printf("DEBUG: allocated power buffers, starting correlation loop\n");
    for (int m = 0; m < max_search; m++) {
        float corr_up = 0.0f;
        float corr_down = 0.0f;
        for (int n = 0; n < N_pre; n++) {
            corr_up += samples[m + n] * pre_up.data[n];
            corr_down += samples[m + n] * pre_down.data[n];
        }
        power_up[m] = corr_up * corr_up;
        power_down[m] = corr_down * corr_down;
    }

    // Compute template energies for threshold
    float energy_up = 0.0f;
    float energy_down = 0.0f;
    for (int n = 0; n < N_pre; n++) {
        energy_up += pre_up.data[n] * pre_up.data[n];
        energy_down += pre_down.data[n] * pre_down.data[n];
    }
    float threshold = 1e-4f * (8.0f * energy_up * energy_up + 2.0f * energy_down * energy_down);

    float max_score = 0.0f;
    int best_m = -1;

    for (int m = 0; m < max_search; m++) {
        float score = 0.0f;
        for (int i = 0; i < 8; i++) {
            if (m + i * N_pre < max_search) {
                score += power_up[m + i * N_pre];
            }
        }
        for (int i = 8; i < 10; i++) {
            if (m + i * N_pre < max_search) {
                score += power_down[m + i * N_pre];
            }
        }
        if (score >= threshold) {
            best_m = m;
            max_score = score;
            // Search local window to find absolute peak
            int search_win = N_pre / 2;
            for (int w = 1; w < search_win; w++) {
                if (m + w < max_search) {
                    float local_score = 0.0f;
                    for (int i = 0; i < 8; i++) {
                        if (m + w + i * N_pre < max_search) {
                            local_score += power_up[m + w + i * N_pre];
                        }
                    }
                    for (int i = 8; i < 10; i++) {
                        if (m + w + i * N_pre < max_search) {
                            local_score += power_down[m + w + i * N_pre];
                        }
                    }
                    if (local_score > max_score) {
                        max_score = local_score;
                        best_m = m + w;
                    }
                }
            }
            break;
        }
    }

    free(power_up);
    free(power_down);

    if (best_m < 0) {
        free(pre_up.data);
        free(pre_down.data);
        *out_bytes = 0;
        return NULL;
    }

    int payload_start = best_m + 10 * N_pre;
    int remaining_samples = (int)len - payload_start;
    int num_symbols = remaining_samples / N_sym;
    if (num_symbols <= 0) {
        free(pre_up.data);
        free(pre_down.data);
        *out_bytes = 0;
        return NULL;
    }

    int num_bytes = (num_symbols + 7) / 8;
    uint8_t* decoded = (uint8_t*)calloc(num_bytes, sizeof(uint8_t));
    if (!decoded) {
        free(pre_up.data);
        free(pre_down.data);
        *out_bytes = 0;
        return NULL;
    }

    for (int s = 0; s < num_symbols; s++) {
        float corr_up = 0.0f;
        float corr_down = 0.0f;
        int sym_offset = payload_start + s * N_sym;
        for (int n = 0; n < N_sym; n++) {
            corr_up += samples[sym_offset + n] * pre_up.data[n];
            corr_down += samples[sym_offset + n] * pre_down.data[n];
        }
        int bit_val = (corr_up * corr_up >= corr_down * corr_down) ? 0 : 1;
        decoded[s / 8] |= (bit_val << (7 - (s % 8)));
    }

    free(pre_up.data);
    free(pre_down.data);

    *out_bytes = num_bytes;
    return decoded;
}

uint8_t* css_demodulate_frame(const float* samples, size_t len,
                               const css_config_t* cfg, size_t* out_bytes) {
    if (!cfg) {
        if (out_bytes) *out_bytes = 0;
        return NULL;
    }
    sw_config sw_cfg = { 0 };
    sw_cfg.sample_rate = (int)cfg->sample_rate;
    sw_cfg.sf = cfg->sf;
    sw_cfg.carrier_freq = cfg->f0;
    sw_cfg.bandwidth = cfg->bandwidth;
    sw_cfg.symbol_duration = (float)(1 << cfg->sf) / cfg->bandwidth;
    sw_cfg.amplitude = 1.0f;

    return css_demodulate(samples, len, sw_cfg, out_bytes);
}

int css_detect_and_sync(const float* samples, int len, int SF, int N, float* timing_offset) {
    (void)SF;
    if (len < N * 10 || !timing_offset) return 0;

    // Use default preamble parameters
    double f0 = 18000.0;
    double B = 4000.0;
    double fs = 44100.0;
    double T = (double)N / fs;
    double amplitude = 0.8;

    sw_signal pre_up = css_generate_chirp(f0, B, T, amplitude, 0.0, fs);
    sw_signal pre_down = css_generate_chirp(f0, -B, T, amplitude, 0.0, fs);

    if (!pre_up.data || !pre_down.data) {
        free(pre_up.data);
        free(pre_down.data);
        return 0;
    }

    int max_search = len - 10 * N;
    if (max_search <= 0) {
        free(pre_up.data);
        free(pre_down.data);
        return 0;
    }

    float* power_up = (float*)calloc(max_search, sizeof(float));
    float* power_down = (float*)calloc(max_search, sizeof(float));
    if (!power_up || !power_down) {
        free(pre_up.data);
        free(pre_down.data);
        free(power_up);
        free(power_down);
        return 0;
    }

    for (int m = 0; m < max_search; m++) {
        float corr_up = 0.0f;
        float corr_down = 0.0f;
        for (int n = 0; n < N; n++) {
            corr_up += samples[m + n] * pre_up.data[n];
            corr_down += samples[m + n] * pre_down.data[n];
        }
        power_up[m] = corr_up * corr_up;
        power_down[m] = corr_down * corr_down;
    }

    float max_score = 0.0f;
    int best_m = -1;

    for (int m = 0; m < max_search; m++) {
        float score = 0.0f;
        for (int i = 0; i < 8; i++) {
            if (m + i * N < max_search) {
                score += power_up[m + i * N];
            }
        }
        for (int i = 8; i < 10; i++) {
            if (m + i * N < max_search) {
                score += power_down[m + i * N];
            }
        }
        if (score > max_score) {
            max_score = score;
            best_m = m;
        }
    }

    free(power_up);
    free(power_down);

    float energy_up = 0.0f;
    float energy_down = 0.0f;
    for (int n = 0; n < N; n++) {
        energy_up += pre_up.data[n] * pre_up.data[n];
        energy_down += pre_down.data[n] * pre_down.data[n];
    }
    float threshold = 1e-4f * (8.0f * energy_up * energy_up + 2.0f * energy_down * energy_down);

    free(pre_up.data);
    free(pre_down.data);

    if (best_m >= 0 && max_score >= threshold) {
        *timing_offset = (float)best_m;
        return 1;
    }

    return 0;
}

void css_generate_downchirp(int N, float fs, float f0, float B, float* out) {
    float mu = B / ((float)N / fs);
    for (int n = 0; n < N; n++) {
        float t = (float)n / fs;
        float phase = -SW_TWO_PI * (f0 * t + 0.5f * mu * t * t);
        out[n] = cosf(phase);
    }
}
