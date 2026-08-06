// OFDM modulator: constellation mapping, pilot insertion, IDFT, cyclic prefix.
// References: MATHEMATICAL_MODEL.md section 2.2.2.

#include "soundwave/ofdm.h"
#include "soundwave/sync.h"
#include "soundwave/common.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

static int get_bit(const uint8_t* bits, size_t bit_idx) {
    return (bits[bit_idx / 8] >> (7 - (bit_idx % 8))) & 1;
}

void ofdm_init(ofdm_config_t* cfg) {
    if (!cfg) return;
    if (cfg->num_subcarriers <= 0) cfg->num_subcarriers = 256;
    if (cfg->cp_length <= 0) cfg->cp_length = cfg->num_subcarriers / 8;
    if (cfg->pilot_spacing <= 0) cfg->pilot_spacing = 8;
    if (cfg->pilot_boost <= 0.0f) cfg->pilot_boost = 1.0f;
}

void bpsk_map(int bit, kiss_fft_cpx* out) {
    out->r = (bit == 0) ? -1.0f : 1.0f;
    out->i = 0.0f;
}

int bpsk_demap(kiss_fft_cpx symbol) {
    return (symbol.r > 0.0f) ? 1 : 0;
}

void qpsk_map(uint8_t dibit, kiss_fft_cpx* out) {
    float val = 0.70710678f; // 1 / sqrt(2)
    switch (dibit) {
        case 0: // 00
            out->r = val;
            out->i = val;
            break;
        case 1: // 01
            out->r = -val;
            out->i = val;
            break;
        case 3: // 11
            out->r = -val;
            out->i = -val;
            break;
        case 2: // 10
            out->r = val;
            out->i = -val;
            break;
        default:
            out->r = 0.0f;
            out->i = 0.0f;
            break;
    }
}

uint8_t qpsk_demap_hard(kiss_fft_cpx symbol) {
    int first = (symbol.r > 0.0f) ? 1 : 0;
    int second = (symbol.i > 0.0f) ? 1 : 0;

    // Inverse of qpsk_map:
    if (first == 1 && second == 1) return 0; // 00
    if (first == 0 && second == 1) return 1; // 01
    if (first == 0 && second == 0) return 3; // 11
    if (first == 1 && second == 0) return 2; // 10
    return 0;
}

void ofdm_allocate_subcarriers(int N, int* data_indices, int* pilot_indices, int* null_indices,
                               int* num_data, int* num_pilots, int* num_nulls) {
    int N_guard = N / 8;
    int n_data = 0;
    int n_pilots = 0;
    int n_nulls = 0;

    // DC Null
    if (null_indices) null_indices[n_nulls] = 0;
    n_nulls++;

    // Guard left
    for (int k = 1; k <= N_guard; k++) {
        if (null_indices) null_indices[n_nulls] = k;
        n_nulls++;
    }

    // Active subcarriers in the independent first half [N_guard + 1 .. N/2 - 1]
    int active_start = N_guard + 1;
    int active_end = N / 2 - 1;
    for (int k = active_start; k <= active_end; k++) {
        if ((k - active_start) % 8 == 0) {
            if (pilot_indices) pilot_indices[n_pilots] = k;
            n_pilots++;
        } else {
            if (data_indices) data_indices[n_data] = k;
            n_data++;
        }
    }

    // Middle Null (N/2)
    if (null_indices) null_indices[n_nulls] = N / 2;
    n_nulls++;

    // Dependent / Conjugate symmetric subcarriers [N/2 + 1 .. N - N_guard - 1]
    for (int k = N / 2 + 1; k <= N - N_guard - 1; k++) {
        if (null_indices) null_indices[n_nulls] = k;
        n_nulls++;
    }

    // Guard right
    for (int k = N - N_guard; k < N; k++) {
        if (null_indices) null_indices[n_nulls] = k;
        n_nulls++;
    }

    if (num_data) *num_data = n_data;
    if (num_pilots) *num_pilots = n_pilots;
    if (num_nulls) *num_nulls = n_nulls;
}

void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X) {
    if (!cfg || !bits || !X) return;

    int N = cfg->num_subcarriers;
    int* data_indices = (int*)malloc(N * sizeof(int));
    int* pilot_indices = (int*)malloc(N * sizeof(int));
    int* null_indices = (int*)malloc(N * sizeof(int));
    int num_data, num_pilots, num_nulls;

    ofdm_allocate_subcarriers(N, data_indices, pilot_indices, null_indices,
                               &num_data, &num_pilots, &num_nulls);

    memset(X, 0, N * sizeof(kiss_fft_cpx));

    for (int i = 0; i < num_data; i++) {
        int idx = data_indices[i];
        if (cfg->modulation == 0) {
            // BPSK
            int bit = (i < (int)bit_len) ? get_bit(bits, i) : 0;
            bpsk_map(bit, &X[idx]);
        } else {
            // QPSK
            int bit1 = (2 * i < (int)bit_len) ? get_bit(bits, 2 * i) : 0;
            int bit2 = (2 * i + 1 < (int)bit_len) ? get_bit(bits, 2 * i + 1) : 0;
            uint8_t dibit = (bit1 << 1) | bit2;
            qpsk_map(dibit, &X[idx]);
        }
    }

    free(data_indices);
    free(pilot_indices);
    free(null_indices);
}

void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X) {
    if (!cfg || !X) return;

    int N = cfg->num_subcarriers;
    int* data_indices = (int*)malloc(N * sizeof(int));
    int* pilot_indices = (int*)malloc(N * sizeof(int));
    int* null_indices = (int*)malloc(N * sizeof(int));
    int num_data, num_pilots, num_nulls;

    ofdm_allocate_subcarriers(N, data_indices, pilot_indices, null_indices,
                               &num_data, &num_pilots, &num_nulls);

    float boost = (cfg->pilot_boost > 0.0f) ? cfg->pilot_boost : 1.0f;
    for (int p = 0; p < num_pilots; p++) {
        int idx = pilot_indices[p];
        X[idx].r = (p % 2 == 0) ? boost : -boost;
        X[idx].i = 0.0f;
    }

    free(data_indices);
    free(pilot_indices);
    free(null_indices);
}

void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time) {
    int N = cfg->num_subcarriers;
    int cp = cfg->cp_length;

    kiss_fft_cfg fft_cfg = kiss_fft_alloc(N, 1, NULL, NULL); // 1 = inverse
    kiss_fft_cpx* temp_in = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* temp_out = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));

    // Enforce conjugate symmetry on temp_in to get purely real time-domain output
    temp_in[0].r = X[0].r;
    temp_in[0].i = 0.0f;
    if (N / 2 < N) {
        temp_in[N / 2].r = X[N / 2].r;
        temp_in[N / 2].i = 0.0f;
    }
    for (int k = 1; k < N / 2; k++) {
        temp_in[k] = X[k];
        temp_in[N - k].r = X[k].r;
        temp_in[N - k].i = -X[k].i; // conjugate
    }

    kiss_fft(fft_cfg, temp_in, temp_out);

    // Normalize by sqrt(N) and copy
    float norm = 1.0f / sqrtf((float)N);
    for (int n = 0; n < N; n++) {
        time[cp + n] = temp_out[n].r * norm;
    }

    // Insert CP
    for (int n = 0; n < cp; n++) {
        time[n] = time[N + n];
    }

    free(temp_in);
    free(temp_out);
    free(fft_cfg);
}

void ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len) {
    if (!cfg || !bits || !samples || !sample_len) return;

    int N = cfg->num_subcarriers;
    int cp = cfg->cp_length;

    int* data_indices = (int*)malloc(N * sizeof(int));
    int* pilot_indices = (int*)malloc(N * sizeof(int));
    int* null_indices = (int*)malloc(N * sizeof(int));
    int num_data, num_pilots, num_nulls;
    ofdm_allocate_subcarriers(N, data_indices, pilot_indices, null_indices,
                               &num_data, &num_pilots, &num_nulls);

    int bits_per_symbol = num_data * (cfg->modulation == 0 ? 1 : 2);
    int num_symbols = (int)((bit_len + bits_per_symbol - 1) / bits_per_symbol);
    if (bit_len == 0) num_symbols = 0;

    size_t total_samples = ((size_t)(2 + num_symbols)) * ((size_t)(N + cp));
    if (total_samples > *sample_len) {
        num_symbols = (int)(*sample_len / (N + cp)) - 2;
        if (num_symbols < 0) num_symbols = 0;
        total_samples = ((size_t)(2 + num_symbols)) * ((size_t)(N + cp));
    }

    // 1. Generate preamble ZC-OFDM symbol
    int N_guard = N / 8;
    int N_active = N / 2 - N_guard - 1;
    int active_start = N_guard + 1;
    float* zc_real = (float*)malloc(N_active * sizeof(float));
    float* zc_imag = (float*)malloc(N_active * sizeof(float));
    sync_zc_generate(1, N_active, zc_real, zc_imag);

    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    for (int i = 0; i < N_active; i++) {
        int idx = active_start + i;
        X[idx].r = zc_real[i];
        X[idx].i = zc_imag[i];
    }

    // Modulate preamble symbol 1
    ofdm_modulate_symbol(cfg, X, samples);
    // Copy to preamble symbol 2
    memcpy(samples + (N + cp), samples, (N + cp) * sizeof(float));

    free(zc_real);
    free(zc_imag);

    // 2. Generate data symbols
    for (int s = 0; s < num_symbols; s++) {
        memset(X, 0, N * sizeof(kiss_fft_cpx));
        for (int i = 0; i < num_data; i++) {
            int idx = data_indices[i];
            size_t bit_pos = s * bits_per_symbol + i * (cfg->modulation == 0 ? 1 : 2);
            if (cfg->modulation == 0) {
                int bit = (bit_pos < bit_len) ? get_bit(bits, bit_pos) : 0;
                bpsk_map(bit, &X[idx]);
            } else {
                int bit1 = (bit_pos < bit_len) ? get_bit(bits, bit_pos) : 0;
                int bit2 = ((bit_pos + 1) < bit_len) ? get_bit(bits, bit_pos + 1) : 0;
                uint8_t dibit = (bit1 << 1) | bit2;
                qpsk_map(dibit, &X[idx]);
            }
        }
        ofdm_insert_pilots(cfg, X);

        float* sym_dest = samples + (2 + s) * (N + cp);
        ofdm_modulate_symbol(cfg, X, sym_dest);
    }

    free(X);
    free(data_indices);
    free(pilot_indices);
    free(null_indices);

    *sample_len = total_samples;
}

sw_signal ofdm_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg) {
    sw_signal sig;
    sig.data = NULL;
    sig.length = 0;
    sig.sample_rate = (float)cfg.sample_rate;

    ofdm_config_t ofdm_cfg;
    ofdm_cfg.num_subcarriers = cfg.num_subcarriers;
    ofdm_cfg.cp_length = cfg.cp_length;
    ofdm_cfg.num_pilots = cfg.num_pilots;
    ofdm_cfg.pilot_spacing = 8;
    ofdm_cfg.pilot_boost = 1.0f;
    ofdm_cfg.modulation = (cfg.sf == 1) ? 0 : 1; // 0 = BPSK, 1 = QPSK

    ofdm_init(&ofdm_cfg);

    int N = ofdm_cfg.num_subcarriers;
    int cp = ofdm_cfg.cp_length;
    int N_guard = N / 8;
    int num_data = N / 2 - N_guard - 1;
    int num_pilots = (num_data + 7) / 8;
    num_data -= num_pilots;

    int bits_per_symbol = num_data * (ofdm_cfg.modulation == 0 ? 1 : 2);
    int num_symbols = (int)((num_bits + bits_per_symbol - 1) / bits_per_symbol);
    if (num_bits == 0) num_symbols = 0;

    size_t total_samples = ((size_t)2 + (size_t)num_symbols) * ((size_t)N + (size_t)cp);
    sig.data = (float*)malloc(total_samples * sizeof(float));
    if (!sig.data) return sig;

    sig.length = total_samples;
    ofdm_modulate_frame(&ofdm_cfg, bits, num_bits, sig.data, &sig.length);
    return sig;
}

sw_signal ofdm_idft_modulate(const kiss_fft_cpx* X, int N, int cp_length, float* temp_buffer) {
    (void)temp_buffer;
    sw_signal sig;
    sig.data = (float*)malloc((N + cp_length) * sizeof(float));
    sig.length = N + cp_length;
    sig.sample_rate = 44100.0f;

    ofdm_config_t cfg;
    cfg.num_subcarriers = N;
    cfg.cp_length = cp_length;
    cfg.pilot_spacing = 8;
    cfg.pilot_boost = 1.0f;
    cfg.modulation = 1;

    ofdm_modulate_symbol(&cfg, X, sig.data);
    return sig;
}
