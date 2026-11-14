// OFDM modulator: band plan, constellation mapping, pilot insertion, IDFT,
// cyclic prefix and transmit windowing (WOLA).
// References: MATHEMATICAL_MODEL.md section 2.2.2.

#include "soundwave/ofdm.h"
#include "soundwave/sync.h"
#include "soundwave/common.h"
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>

static int get_bit(const uint8_t* bits, size_t bit_idx) {
    return (bits[bit_idx / 8] >> (7 - (bit_idx % 8))) & 1;
}

void ofdm_init(ofdm_config_t* cfg) {
    if (!cfg) return;
    if (cfg->num_subcarriers <= 0) cfg->num_subcarriers = 256;
    if (cfg->cp_length <= 0) cfg->cp_length = cfg->num_subcarriers / 8;
    if (cfg->pilot_spacing <= 0) cfg->pilot_spacing = OFDM_PILOT_SPACING;
    if (cfg->pilot_boost <= 0.0f) cfg->pilot_boost = 1.0f;
    if (!(cfg->amplitude > 0.0f && cfg->amplitude <= 1.0f))
        cfg->amplitude = OFDM_DEFAULT_AMPLITUDE;
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

static int ofdm_fft_size_ok(int N) {
    return N >= 16 && N <= 4096 && (N & (N - 1)) == 0;
}

int ofdm_layout_compute(int N, float sample_rate, float carrier_freq,
                        float bandwidth, ofdm_layout_t* out) {
    if (!out) return SW_ERR_BAD_PARAM;
    memset(out, 0, sizeof *out);
    if (!ofdm_fft_size_ok(N)) return SW_ERR_BAD_PARAM;
    if (!isfinite(sample_rate) || !isfinite(carrier_freq) || !isfinite(bandwidth) ||
        sample_rate < 0.0f || carrier_freq < 0.0f || bandwidth < 0.0f)
        return SW_ERR_BAD_PARAM;
    // Defaults are applied in float, then everything is computed in double
    // with the same operation order as FrameGeometry (soundwave_app), so both
    // sides agree on the bin indices exactly.
    if (sample_rate == 0.0f) sample_rate = OFDM_DEFAULT_SAMPLE_RATE;
    if (carrier_freq == 0.0f) carrier_freq = OFDM_DEFAULT_CARRIER_HZ;
    if (bandwidth == 0.0f) bandwidth = OFDM_DEFAULT_BANDWIDTH_HZ;

    double fs = (double)sample_rate;
    double f_lo = (double)carrier_freq - 0.5 * (double)bandwidth;
    double f_hi = (double)carrier_freq + 0.5 * (double)bandwidth;
    double df = fs / (double)N;
    // The band must sit strictly above DC and leave one subcarrier spacing of
    // guard below Nyquist (anti-aliasing filters roll off there).
    if (!(f_lo > 0.0) || !(f_hi <= 0.5 * fs - df)) return SW_ERR_BAD_PARAM;

    double k_lo = ceil(f_lo * (double)N / fs) + OFDM_EDGE_GUARD_BINS;
    double k_hi = floor(f_hi * (double)N / fs) - OFDM_EDGE_GUARD_BINS;
    if (k_lo < 1.0 || k_hi > 0.5 * (double)N - 1.0 ||
        k_hi - k_lo + 1.0 < (double)OFDM_MIN_ACTIVE_BINS)
        return SW_ERR_BAD_PARAM;

    out->first_bin = (int)k_lo;
    out->last_bin = (int)k_hi;
    out->num_active = out->last_bin - out->first_bin + 1;
    out->num_pilots = (out->num_active + OFDM_PILOT_SPACING - 1) / OFDM_PILOT_SPACING;
    out->num_data = out->num_active - out->num_pilots;
    return SW_OK;
}

int ofdm_layout_from_config(const ofdm_config_t* cfg, ofdm_layout_t* out) {
    if (!cfg) {
        if (out) memset(out, 0, sizeof *out);
        return SW_ERR_BAD_PARAM;
    }
    int N = cfg->num_subcarriers > 0 ? cfg->num_subcarriers : 256;
    return ofdm_layout_compute(N, cfg->sample_rate, cfg->carrier_freq,
                               cfg->bandwidth, out);
}

void ofdm_allocate_subcarriers(const ofdm_layout_t* lay, int* data_indices,
                               int* pilot_indices) {
    if (!lay) return;
    int n_data = 0, n_pilots = 0;
    for (int k = lay->first_bin; k <= lay->last_bin; k++) {
        if ((k - lay->first_bin) % OFDM_PILOT_SPACING == 0) {
            if (pilot_indices) pilot_indices[n_pilots] = k;
            n_pilots++;
        } else {
            if (data_indices) data_indices[n_data] = k;
            n_data++;
        }
    }
}

int ofdm_preamble_spectrum(const ofdm_layout_t* lay, int N, int cp, kiss_fft_cpx* X) {
    if (!lay || !X || N <= 0 || cp < 0 || cp > N || lay->num_active <= 0 ||
        lay->first_bin < 1 || lay->last_bin >= N / 2)
        return SW_ERR_BAD_PARAM;
    float* zr = (float*)malloc((size_t)lay->num_active * sizeof(float));
    float* zi = (float*)malloc((size_t)lay->num_active * sizeof(float));
    if (!zr || !zi) {
        free(zr);
        free(zi);
        return SW_ERR_MEMORY;
    }
    sync_zc_generate(1, lay->num_active, zr, zi);

    // The two preamble copies are joined without a cross-fade, so the
    // waveform jumps from body[N-1] to the second copy's CP sample
    // body[N-cp] instead of continuing with body[0]. A common phase
    // rotation e^{j phi} of the whole sequence (still a ZC sequence, so the
    // receiver's template, which comes from this function too, is identical)
    // makes Re{e^{j phi} (z[N-cp] - z[0])} = 0, z[n] = sum_k X_k e^{j2pi kn/N}:
    // the junction is then continuous in value and its spectral splatter
    // falls off as 1/f^4 instead of 1/f^2.
    double dr = 0.0, di = 0.0;
    for (int i = 0; i < lay->num_active; i++) {
        int k = lay->first_bin + i;
        double a = 2.0 * (double)SW_PI * (double)k * (double)(N - cp) / (double)N;
        double ca = cos(a), sa = sin(a);
        dr += (double)zr[i] * ca - (double)zi[i] * sa - (double)zr[i];
        di += (double)zr[i] * sa + (double)zi[i] * ca - (double)zi[i];
    }
    double rot_r = 1.0, rot_i = 0.0;
    double dmag = sqrt(dr * dr + di * di);
    if (dmag > 1e-9 * (double)lay->num_active) {
        // e^{j phi} = j * conj(dz) / |dz|  =>  e^{j phi} dz = j |dz|
        rot_r = di / dmag;
        rot_i = dr / dmag;
    }

    memset(X, 0, (size_t)N * sizeof(kiss_fft_cpx));
    for (int i = 0; i < lay->num_active; i++) {
        X[lay->first_bin + i].r = (float)((double)zr[i] * rot_r - (double)zi[i] * rot_i);
        X[lay->first_bin + i].i = (float)((double)zr[i] * rot_i + (double)zi[i] * rot_r);
    }
    free(zr);
    free(zi);
    return SW_OK;
}

void ofdm_scramble(uint8_t* bits, size_t nbits) {
    if (!bits) return;
    unsigned state = 0x7FFFu;
    for (size_t i = 0; i < nbits; i++) {
        unsigned pn = ((state >> 14) ^ (state >> 13)) & 1u;
        state = ((state << 1) | pn) & 0x7FFFu;
        if (pn) bits[i / 8] ^= (uint8_t)(0x80u >> (i % 8));
    }
}

void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X) {
    if (!cfg || !bits || !X) return;
    ofdm_layout_t lay;
    if (ofdm_layout_from_config(cfg, &lay) != SW_OK) return;
    int N = cfg->num_subcarriers > 0 ? cfg->num_subcarriers : 256;
    int* data_indices = (int*)calloc((size_t)lay.num_data, sizeof(int));
    if (!data_indices) return;
    ofdm_allocate_subcarriers(&lay, data_indices, NULL);

    memset(X, 0, (size_t)N * sizeof(kiss_fft_cpx));
    for (int i = 0; i < lay.num_data; i++) {
        int idx = data_indices[i];
        if (cfg->modulation == 0) {
            int bit = ((size_t)i < bit_len) ? get_bit(bits, (size_t)i) : 0;
            bpsk_map(bit, &X[idx]);
        } else {
            size_t b = 2 * (size_t)i;
            int bit1 = (b < bit_len) ? get_bit(bits, b) : 0;
            int bit2 = (b + 1 < bit_len) ? get_bit(bits, b + 1) : 0;
            qpsk_map((uint8_t)((bit1 << 1) | bit2), &X[idx]);
        }
    }
    free(data_indices);
}

void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X) {
    if (!cfg || !X) return;
    ofdm_layout_t lay;
    if (ofdm_layout_from_config(cfg, &lay) != SW_OK) return;
    float boost = (cfg->pilot_boost > 0.0f) ? cfg->pilot_boost : 1.0f;
    for (int p = 0; p < lay.num_pilots; p++) {
        int idx = lay.first_bin + p * OFDM_PILOT_SPACING;
        X[idx].r = (p % 2 == 0) ? boost : -boost;
        X[idx].i = 0.0f;
    }
}

void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time) {
    if (!cfg || !X || !time || cfg->num_subcarriers <= 0 || cfg->cp_length < 0) return;
    int N = cfg->num_subcarriers;
    int cp = cfg->cp_length;

    kiss_fft_cfg fft_cfg = kiss_fft_alloc(N, 1, NULL, NULL); // 1 = inverse
    kiss_fft_cpx* temp_in = (kiss_fft_cpx*)malloc((size_t)N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* temp_out = (kiss_fft_cpx*)malloc((size_t)N * sizeof(kiss_fft_cpx));
    if (!fft_cfg || !temp_in || !temp_out) {
        // Emit silence rather than dereferencing NULL on allocation failure.
        memset(time, 0, ((size_t)N + (size_t)cp) * sizeof(float));
        free(temp_in);
        free(temp_out);
        free(fft_cfg);
        return;
    }

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

// Overlap-adds one symbol (CP + body: L = N + cp samples in sym) at out with
// a raised-cosine rise over its first W samples (if rise) and, if suffix, its
// cyclic suffix sym[cp .. cp + W) fading out over the W samples after it.
// The destination must be zeroed beforehand.
static void ofdm_wola_add(float* out, const float* sym, int N, int cp, int W,
                          const float* ramp, int rise, int suffix) {
    int L = N + cp;
    for (int n = 0; n < L; n++) {
        float g = (rise && n < W) ? ramp[n] : 1.0f;
        out[n] += g * sym[n];
    }
    if (suffix) {
        for (int n = 0; n < W; n++) out[L + n] += ramp[W - 1 - n] * sym[cp + n];
    }
}

float ofdm_peak_normalize(float* samples, size_t len, float amplitude) {
    if (!samples || len == 0 || !(amplitude > 0.0f)) return 0.0f;
    float peak = 0.0f;
    for (size_t i = 0; i < len; i++) {
        float a = fabsf(samples[i]);
        if (a > peak) peak = a;
    }
    if (!(peak > 0.0f)) return 0.0f;
    double g = (double)amplitude / (double)peak;
    for (size_t i = 0; i < len; i++) {
        float v = (float)((double)samples[i] * g);
        // Rounding can land one ulp above the target; the contract is exact.
        if (v > amplitude) v = amplitude;
        else if (v < -amplitude) v = -amplitude;
        samples[i] = v;
    }
    return (float)g;
}

int ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len) {
    if (!cfg || !bits || !samples || !sample_len) return SW_ERR_BAD_PARAM;

    int N = cfg->num_subcarriers;
    int cp = cfg->cp_length;
    if (!ofdm_fft_size_ok(N) || cp < 0 || cp > N) return SW_ERR_BAD_PARAM;

    ofdm_layout_t lay;
    if (ofdm_layout_from_config(cfg, &lay) != SW_OK) return SW_ERR_BAD_PARAM;

    int bits_per_symbol = lay.num_data * (cfg->modulation == 0 ? 1 : 2);
    size_t num_symbols =
        bit_len ? (bit_len + (size_t)bits_per_symbol - 1) / (size_t)bits_per_symbol : 0;
    size_t L = (size_t)N + (size_t)cp;
    int W = OFDM_WOLA_LEN(cp);
    if (num_symbols > (size_t)INT_MAX || num_symbols + 3 > SIZE_MAX / sizeof(float) / L)
        return SW_ERR_BAD_PARAM; // would overflow the size computation below
    size_t total_samples = (2 + num_symbols) * L + (size_t)W;
    if (*sample_len < 2 * L + (size_t)W) {
        // Not even room for the preamble and its fade-out.
        *sample_len = 0;
        return SW_ERR_OVERFLOW;
    }
    if (total_samples > *sample_len) {
        *sample_len = total_samples; // required size
        return SW_ERR_OVERFLOW;
    }

    int* data_indices = (int*)calloc((size_t)lay.num_data, sizeof(int));
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    float* sym = (float*)calloc(L, sizeof(float));
    float* ramp = (float*)malloc(((size_t)W + 1) * sizeof(float));
    // Every data subcarrier of every symbol carries a bit: the payload,
    // then zero padding up to the end of the last symbol.
    size_t air_bits = num_symbols * (size_t)bits_per_symbol;
    uint8_t* wbits = (uint8_t*)calloc(air_bits / 8 + 1, 1);
    if (!data_indices || !X || !sym || !ramp || !wbits) {
        free(data_indices); free(X); free(sym); free(ramp); free(wbits);
        return SW_ERR_MEMORY;
    }
    // Whitened copy of the data bits, padding included (see ofdm_scramble):
    // unwhitened padding would put the same point on hundreds of
    // subcarriers of the last symbol, i.e. a coherent time-domain pulse with
    // a crest factor of up to ~26 dB, and peak normalization would then make
    // the whole frame that much quieter. The receiver descrambles every
    // demodulated bit, so the padding still decodes as zeros.
    memcpy(wbits, bits, (bit_len + 7) / 8);
    if (bit_len % 8) wbits[bit_len / 8] &= (uint8_t)(0xFFu << (8 - bit_len % 8));
    ofdm_scramble(wbits, air_bits);
    bits = wbits;
    ofdm_allocate_subcarriers(&lay, data_indices, NULL);
    // Raised-cosine rise r[n]; the matching fall is r[W - 1 - n], and
    // r[n] + r[W - 1 - n] = 1, so overlapping symbols cross-fade at unit gain.
    for (int n = 0; n < W; n++)
        ramp[n] = 0.5f * (1.0f - cosf(SW_PI * ((float)n + 0.5f) / (float)W));

    memset(samples, 0, total_samples * sizeof(float));

    // 1. Preamble: the same ZC-OFDM symbol twice. The two copies are joined
    // without a cross-fade so they stay sample-identical (Schmidl-Cox timing
    // and CFO); only the frame start and the junction to the first data
    // symbol are windowed.
    int rc = ofdm_preamble_spectrum(&lay, N, cp, X);
    if (rc != SW_OK) {
        free(data_indices); free(X); free(sym); free(ramp); free(wbits);
        return rc;
    }
    ofdm_modulate_symbol(cfg, X, sym);
    ofdm_wola_add(samples, sym, N, cp, W, ramp, 1, 0);
    ofdm_wola_add(samples + L, sym, N, cp, W, ramp, 0, 1);

    // 2. Data symbols
    int bits_per_sub = (cfg->modulation == 0 ? 1 : 2);
    for (size_t s = 0; s < num_symbols; s++) {
        memset(X, 0, (size_t)N * sizeof(kiss_fft_cpx));
        for (int i = 0; i < lay.num_data; i++) {
            int idx = data_indices[i];
            size_t bit_pos = s * (size_t)bits_per_symbol + (size_t)i * (size_t)bits_per_sub;
            // bit_pos < air_bits: the whitened buffer covers every symbol.
            if (cfg->modulation == 0) {
                bpsk_map(get_bit(bits, bit_pos), &X[idx]);
            } else {
                int bit1 = get_bit(bits, bit_pos);
                int bit2 = get_bit(bits, bit_pos + 1);
                qpsk_map((uint8_t)((bit1 << 1) | bit2), &X[idx]);
            }
        }
        ofdm_insert_pilots(cfg, X);
        ofdm_modulate_symbol(cfg, X, sym);
        ofdm_wola_add(samples + (2 + s) * L, sym, N, cp, W, ramp, 1, 1);
    }

    free(data_indices);
    free(X);
    free(sym);
    free(ramp);
    free(wbits);

    // Peak normalization (MATHEMATICAL_MODEL.md 2.2.3): the IDFT output's
    // peak depends on N, the band and the payload (crest factor ~3-5), so the
    // raw frame can exceed full scale. One gain per frame keeps the spectrum
    // shape (and the ultrasonic confinement) intact, unlike clipping.
    float amp = (cfg->amplitude > 0.0f && cfg->amplitude <= 1.0f)
                    ? cfg->amplitude : OFDM_DEFAULT_AMPLITUDE;
    ofdm_peak_normalize(samples, total_samples, amp);

    *sample_len = total_samples;
    return SW_OK;
}

sw_signal ofdm_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg) {
    sw_signal sig;
    sig.data = NULL;
    sig.length = 0;
    sig.sample_rate = (float)(cfg.sample_rate > 0 ? cfg.sample_rate : 44100);

    ofdm_config_t ofdm_cfg;
    memset(&ofdm_cfg, 0, sizeof ofdm_cfg);
    ofdm_cfg.num_subcarriers = cfg.num_subcarriers;
    ofdm_cfg.cp_length = cfg.cp_length;
    ofdm_cfg.num_pilots = cfg.num_pilots;
    ofdm_cfg.pilot_spacing = OFDM_PILOT_SPACING;
    ofdm_cfg.pilot_boost = 1.0f;
    ofdm_cfg.modulation = cfg.ofdm_modulation; // 0 = BPSK, 1 = QPSK
    ofdm_cfg.sample_rate = cfg.sample_rate > 0 ? (float)cfg.sample_rate : 0.0f;
    ofdm_cfg.carrier_freq = cfg.carrier_freq;
    ofdm_cfg.bandwidth = cfg.bandwidth;
    ofdm_cfg.amplitude = cfg.amplitude; // 0 -> OFDM_DEFAULT_AMPLITUDE

    ofdm_init(&ofdm_cfg);

    ofdm_layout_t lay;
    if (!bits || num_bits == 0 || ofdm_layout_from_config(&ofdm_cfg, &lay) != SW_OK)
        return sig;

    int N = ofdm_cfg.num_subcarriers;
    int cp = ofdm_cfg.cp_length;
    int bits_per_symbol = lay.num_data * (ofdm_cfg.modulation == 0 ? 1 : 2);
    size_t num_symbols = (num_bits + (size_t)bits_per_symbol - 1) / (size_t)bits_per_symbol;
    size_t sym_len = (size_t)N + (size_t)cp;
    if (num_symbols > (size_t)INT_MAX || num_symbols + 3 > SIZE_MAX / sizeof(float) / sym_len)
        return sig; // would overflow the size computation below

    size_t total_samples = (2 + num_symbols) * sym_len + (size_t)OFDM_WOLA_LEN(cp);
    sig.data = (float*)malloc(total_samples * sizeof(float));
    if (!sig.data) return sig;

    sig.length = total_samples;
    if (ofdm_modulate_frame(&ofdm_cfg, bits, num_bits, sig.data, &sig.length) != SW_OK) {
        // Never hand back a partially written (uninitialised) buffer as success.
        free(sig.data);
        sig.data = NULL;
        sig.length = 0;
    }
    return sig;
}
