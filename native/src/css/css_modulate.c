// CSS modulator: LoRa-style chirp symbols carrying SF bits each.
// References: MATHEMATICAL_MODEL.md section 2.1.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <stdlib.h>

#define CSS_MAX_CHIRP_SAMPLES (1 << 20)
#define CSS_TWO_PI_D 6.283185307179586476925

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

int css_geometry(const sw_config* cfg, css_geometry_t* g) {
    if (!cfg || !g) return -1;
    int sf = cfg->sf > 0 ? cfg->sf : CSS_DEFAULT_SF;
    double fs = cfg->sample_rate > 0 ? (double)cfg->sample_rate : 44100.0;
    double fc = (double)cfg->carrier_freq;
    double bw = (double)cfg->bandwidth;
    double amp = (double)cfg->amplitude;
    if (!isfinite(fc) || !isfinite(bw) || !isfinite(amp)) return -1;
    if (fc <= 0.0) fc = 19000.0;
    if (bw <= 0.0) bw = 2000.0;
    if (amp <= 0.0) amp = 0.8;
    // Constant-envelope chirps: the frame peak is exactly amp (<= full scale).
    if (amp > 1.0) return -1;
    if (sf < CSS_MIN_SF || sf > CSS_MAX_SF) return -1;
    if (fs < 1000.0 || fs > 1.0e6) return -1;

    // Integer samples per chip: the effective bandwidth is fs / D, so a
    // symbol is exactly M * D samples and every chip boundary falls on a
    // sample (see MATHEMATICAL_MODEL.md section 2.1).
    double ratio = fs / bw;
    if (!isfinite(ratio) || ratio > 1.0e6) return -1;
    long d = lround(ratio);
    if (d < 1) d = 1;
    int M = 1 << sf;
    double n = (double)M * (double)d;
    if (n > CSS_MAX_SYMBOL_SEC * fs + 0.5 || n > (double)CSS_MAX_CHIRP_SAMPLES) return -1;
    double B = fs / (double)d;
    // The whole band must lie in (0, fs/2].
    if (fc - 0.5 * B <= 0.0 || fc + 0.5 * B > 0.5 * fs) return -1;

    g->sf = sf;
    g->M = M;
    g->D = (int)d;
    g->N = (int)n;
    g->fs = fs;
    g->fc = fc;
    g->B = B;
    g->amplitude = amp;
    return 0;
}

size_t css_num_symbols(const css_geometry_t* g, size_t num_bits) {
    size_t sf = (size_t)g->sf;
    return num_bits / sf + (num_bits % sf != 0);
}

size_t css_frame_samples(const css_geometry_t* g, size_t num_bits) {
    size_t nsym = css_num_symbols(g, num_bits);
    size_t N = (size_t)g->N;
    size_t max_sym = (SIZE_MAX / sizeof(float)) / N;
    if (max_sym < CSS_PREAMBLE_SYMBOLS || nsym > max_sym - CSS_PREAMBLE_SYMBOLS) return 0;
    return (nsym + CSS_PREAMBLE_SYMBOLS) * N;
}

// Gray decode: the symbol k whose Gray code k ^ (k >> 1) equals v, so that
// symbols one bin apart (the most likely error) differ in one bit.
static int gray_inverse(int v) {
    int k = v;
    for (int s = 1; s < 31; s <<= 1) k ^= k >> s;
    return k;
}

// Writes one chirp symbol starting at phase *phase0 (cycles), advancing it so
// consecutive symbols are phase continuous. down != 0 writes a down-chirp,
// otherwise the base up-chirp cyclically shifted by k chips: its frequency
// starts at f_lo + k B / M, rises at B / T and wraps from f_hi to f_lo at
// sample (M - k) D.
static void write_symbol(const css_geometry_t* g, int k, int down,
                         double* phase0, float* out) {
    const double fs = g->fs, B = g->B;
    const double T = (double)g->M / B;
    const double rate = B / T; // Hz per second
    const double f_lo = g->fc - 0.5 * B, f_hi = g->fc + 0.5 * B;
    const int N = g->N;
    const int nw = (g->M - k) * g->D; // wrap sample (N when k == 0)
    const double tw = (double)nw / fs;
    const double f_start = f_lo + (double)k * B / (double)g->M;
    const double ph_w = f_start * tw + 0.5 * rate * tw * tw;
    double p0 = *phase0;

    for (int n = 0; n <= N; n++) {
        double t = (double)n / fs, ph;
        if (down) {
            ph = f_hi * t - 0.5 * rate * t * t;
        } else if (n < nw) {
            ph = f_start * t + 0.5 * rate * t * t;
        } else {
            double u = t - tw;
            ph = ph_w + f_lo * u + 0.5 * rate * u * u;
        }
        if (n == N) {
            *phase0 = fmod(p0 + ph, 1.0);
            break;
        }
        double c = fmod(p0 + ph, 1.0);
        out[n] = (float)(g->amplitude * cos(CSS_TWO_PI_D * c));
    }
}

void css_modulate_into(const css_geometry_t* g, const uint8_t* bits,
                       size_t num_bits, float* out) {
    double phase = 0.0;
    size_t N = (size_t)g->N;
    for (int i = 0; i < CSS_PREAMBLE_UP; i++, out += N) write_symbol(g, 0, 0, &phase, out);
    for (int i = 0; i < CSS_PREAMBLE_DOWN; i++, out += N) write_symbol(g, 0, 1, &phase, out);

    size_t nsym = css_num_symbols(g, num_bits);
    size_t bit = 0;
    for (size_t s = 0; s < nsym; s++, out += N) {
        int v = 0;
        for (int b = 0; b < g->sf; b++, bit++) {
            int x = 0;
            if (bit < num_bits) x = (bits[bit / 8] >> (7 - (bit % 8))) & 1;
            v = (v << 1) | x;
        }
        write_symbol(g, gray_inverse(v), 0, &phase, out);
    }
}

sw_signal css_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg) {
    sw_signal sig;
    sig.data = NULL;
    sig.length = 0;
    sig.sample_rate = 0.0f;
    css_geometry_t g;
    if (!bits || num_bits == 0 || css_geometry(&cfg, &g) != 0) return sig;
    size_t total = css_frame_samples(&g, num_bits);
    if (total == 0) return sig;
    sig.data = (float*)malloc(total * sizeof(float));
    if (!sig.data) return sig;
    css_modulate_into(&g, bits, num_bits, sig.data);
    sig.length = total;
    sig.sample_rate = (float)g.fs;
    return sig;
}

// ---------------------------------------------------------------------------
// Legacy single-chirp helpers (css_config_t)
// ---------------------------------------------------------------------------

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
