// CSS demodulator: complex baseband conversion, preamble search, dechirp + FFT
// symbol decisions. References: MATHEMATICAL_MODEL.md sections 2.1.4 and 3.1.
//
// Receiver chain
//   1. z[n] = LPF{ r[n] e^{-j 2 pi fc n / fs} }   (full-rate complex baseband;
//      windowed-sinc low-pass at 0.6 B removes the negative-frequency image
//      and out-of-band noise)
//   2. preamble metric at start m: U(m) = mean over the 8 up-chirp slots of
//      |<z_slot, up>|^2 / (N * Ebar), Dn(m) the smaller of the same score
//      for the 2 down-chirp slots with the down-chirp, Ebar = mean window
//      energy of all 10 slots.
//      Both lie in [0, 1] for a real preamble, whatever the signal level.
//   3. The first m where both exceed the threshold opens a one-symbol search
//      region; the start is the maximum of U + Dn there. Data are up-chirps
//      only, so Dn
//      stays at the noise level (~1 / (2M)) inside any payload.
//   4. A carrier/Doppler offset delays the up-chirp correlation peak and
//      advances the down-chirp peak by the same amount, so their midpoint is
//      the timing and their half-difference the offset (B / N Hz per sample).
//   5. Each data symbol: sample z at the chip instants (linear interpolation
//      at the fractional start), remove the offset, multiply by the conjugate
//      base chirp, M-point FFT, argmax -> Gray code -> SF bits.

#include "soundwave/css.h"
#include "soundwave/common.h"
#include "kiss_fft.h"
#include <string.h>
#include <limits.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>

#define CSS_TWO_PI_D        6.283185307179586476925
#define CSS_MAX_INPUT       ((size_t)1 << 27) // 128 M samples (~50 min at 44.1 kHz)
#define CSS_ENERGY_GATE     1e-6              // windows quieter than this * max are ignored

static size_t next_pow2(size_t v) {
    size_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

// R[m] = sum_{n<S} y[m+n] * conj(s[n]) for m < count (overlap-save FFT).
static int cxcorr(const kiss_fft_cpx* y, size_t Y, const kiss_fft_cpx* s, size_t S,
                  kiss_fft_cpx* R, size_t count) {
    if (!y || !s || !R || S == 0 || Y < S || count > Y - S + 1) return -1;
    size_t nfft = next_pow2(2 * S);
    if (nfft < 1024) nfft = 1024;
    if (nfft > ((size_t)1 << 22)) return -1;
    size_t step = nfft - S + 1;

    int rc = -1;
    kiss_fft_cfg fwd = kiss_fft_alloc((int)nfft, 0, NULL, NULL);
    kiss_fft_cfg inv = kiss_fft_alloc((int)nfft, 1, NULL, NULL);
    kiss_fft_cpx* H = (kiss_fft_cpx*)malloc(nfft * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X = (kiss_fft_cpx*)malloc(nfft * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* buf = (kiss_fft_cpx*)malloc(nfft * sizeof(kiss_fft_cpx));
    if (!fwd || !inv || !H || !X || !buf) goto done;

    memset(buf, 0, nfft * sizeof(kiss_fft_cpx));
    memcpy(buf, s, S * sizeof(kiss_fft_cpx));
    kiss_fft(fwd, buf, H);

    const kiss_fft_scalar scale = (kiss_fft_scalar)(1.0 / (double)nfft);
    for (size_t p = 0; p < count; p += step) {
        size_t avail = Y - p;
        size_t take = avail < nfft ? avail : nfft;
        memcpy(buf, y + p, take * sizeof(kiss_fft_cpx));
        if (take < nfft) memset(buf + take, 0, (nfft - take) * sizeof(kiss_fft_cpx));
        kiss_fft(fwd, buf, X);
        for (size_t k = 0; k < nfft; k++) {
            kiss_fft_scalar xr = X[k].r, xi = X[k].i;
            X[k].r = xr * H[k].r + xi * H[k].i;
            X[k].i = xi * H[k].r - xr * H[k].i;
        }
        kiss_fft(inv, X, buf);
        size_t n = count - p < step ? count - p : step;
        for (size_t j = 0; j < n; j++) {
            R[p + j].r = buf[j].r * scale;
            R[p + j].i = buf[j].i * scale;
        }
    }
    rc = 0;
done:
    free(H); free(X); free(buf);
    free(fwd); free(inv);
    return rc;
}

// Full-rate complex baseband of the band fc +/- B/2 (same length as r,
// aligned: the FIR's group delay is compensated). Non-finite input samples
// are treated as 0. Returns NULL on allocation failure.
static kiss_fft_cpx* css_baseband(const float* r, size_t len, const css_geometry_t* g) {
    if (len == 0 || len > CSS_MAX_INPUT || g->D < 1 || g->D > (1 << 20)) return NULL;
    size_t L = 10 * (size_t)g->D + 1;
    size_t h0 = (L - 1) / 2;
    double fcut = 0.6 / (double)g->D; // cycles per sample
    if (fcut > 0.5) fcut = 0.5;

    kiss_fft_cpx* taps = (kiss_fft_cpx*)malloc(L * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* y = (kiss_fft_cpx*)calloc(len + L - 1, sizeof(kiss_fft_cpx));
    kiss_fft_cpx* z = (kiss_fft_cpx*)malloc(len * sizeof(kiss_fft_cpx));
    double* h = (double*)malloc(L * sizeof(double));
    double sum = 0.0;
    if (!taps || !y || !z || !h) goto fail;
    for (size_t n = 0; n < L; n++) {
        double x = (double)n - (double)h0;
        double sinc = (x == 0.0) ? 2.0 * fcut : sin(CSS_TWO_PI_D * fcut * x) / (0.5 * CSS_TWO_PI_D * x);
        double w = 0.54 - 0.46 * cos(CSS_TWO_PI_D * (double)n / (double)(L - 1));
        h[n] = sinc * w;
        sum += h[n];
    }
    for (size_t n = 0; n < L; n++) {
        taps[n].r = (kiss_fft_scalar)(h[n] / sum);
        taps[n].i = 0;
    }

    for (size_t i = 0; i < len; i++) {
        double x = isfinite(r[i]) ? (double)r[i] : 0.0;
        double ph = fmod(g->fc * (double)i / g->fs, 1.0);
        y[h0 + i].r = (kiss_fft_scalar)(x * cos(CSS_TWO_PI_D * ph));
        y[h0 + i].i = (kiss_fft_scalar)(-x * sin(CSS_TWO_PI_D * ph));
    }
    if (cxcorr(y, len + L - 1, taps, L, z, len) != 0) goto fail;
    free(taps);
    free(y);
    free(h);
    return z;
fail:
    free(taps); free(y); free(z); free(h);
    return NULL;
}

// Full-rate baseband base chirp from -B/2 to +B/2 over N samples.
static void base_chirp(const css_geometry_t* g, kiss_fft_cpx* up, kiss_fft_cpx* dn) {
    const double rate = g->B * g->B / (double)g->M; // B / T
    for (int n = 0; n < g->N; n++) {
        double t = (double)n / g->fs;
        double ph = -0.5 * g->B * t + 0.5 * rate * t * t;
        ph -= floor(ph);
        double c = cos(CSS_TWO_PI_D * ph), s = sin(CSS_TWO_PI_D * ph);
        up[n].r = (kiss_fft_scalar)c; up[n].i = (kiss_fft_scalar)s;
        dn[n].r = (kiss_fft_scalar)c; dn[n].i = (kiss_fft_scalar)(-s);
    }
}

// out[m] = max(a[m-W .. m+W]) (clipped to the array), van Herk / Gil-Werman.
static int sliding_max(const float* a, size_t n, size_t W, float* out) {
    if (n == 0 || W > ((SIZE_MAX / sizeof(float)) - n) / 2 - 1) return -1;
    size_t w = 2 * W + 1, L = n + 2 * W;
    float* p = (float*)calloc(L, sizeof(float));
    float* f = (float*)malloc(L * sizeof(float));
    float* b = (float*)malloc(L * sizeof(float));
    if (!p || !f || !b) {
        free(p); free(f); free(b);
        return -1;
    }
    memcpy(p + W, a, n * sizeof(float)); // values are >= 0; padding is 0
    for (size_t i = 0; i < L; i++)
        f[i] = (i % w == 0) ? p[i] : (p[i] > f[i - 1] ? p[i] : f[i - 1]);
    for (size_t i = L; i-- > 0;)
        b[i] = (i == L - 1 || (i + 1) % w == 0) ? p[i] : (p[i] > b[i + 1] ? p[i] : b[i + 1]);
    for (size_t m = 0; m < n; m++) {
        size_t j = m + w - 1; // < L because L = n + w - 1
        if (j >= L) break;    // (kept explicit for static analysis)
        float x = b[m], y = f[j];
        out[m] = x > y ? x : y;
    }
    free(p); free(f); free(b);
    return 0;
}

// Peak of a[] within c +/- W, refined by a parabola through its neighbours.
static double refine_peak(const float* a, size_t n, size_t c, size_t W) {
    size_t lo = c > W ? c - W : 0;
    size_t hi = c + W < n - 1 ? c + W : n - 1;
    size_t k = lo;
    for (size_t i = lo + 1; i <= hi; i++)
        if (a[i] > a[k]) k = i;
    double d = 0.0;
    if (k > 0 && k + 1 < n) {
        double y0 = a[k - 1], y1 = a[k], y2 = a[k + 1];
        double den = y0 - 2.0 * y1 + y2;
        if (den < 0.0) d = 0.5 * (y0 - y2) / den;
        if (!isfinite(d)) d = 0.0;
        if (d > 0.5) d = 0.5;
        if (d < -0.5) d = -0.5;
    }
    return (double)k + d;
}

// double -> kiss_fft_scalar without overflow (huge but finite inputs would
// otherwise be undefined behaviour on the narrowing conversion).
static kiss_fft_scalar to_scalar(double v) {
    if (v > (double)FLT_MAX) return (kiss_fft_scalar)FLT_MAX;
    if (v < -(double)FLT_MAX) return (kiss_fft_scalar)(-FLT_MAX);
    return (kiss_fft_scalar)v; // also NaN
}

static float clamp_rho(double v) {
    if (!(v >= 0.0)) return 0.0f; // also NaN
    return v > 1.0 ? 1.0f : (float)v;
}

// Preamble search on the complex baseband z (see file header, steps 2-4).
static int css_sync_bb(const kiss_fft_cpx* z, size_t len, const css_geometry_t* g,
                       float threshold, css_sync_result_t* res) {
    const size_t N = (size_t)g->N, D = (size_t)g->D;
    if (N == 0 || D == 0 || len / CSS_PREAMBLE_SYMBOLS < N) return 0;
    const size_t count = len - N + 1;                       // window positions
    const size_t nm = len - CSS_PREAMBLE_SYMBOLS * N + 1;   // preamble starts
    const size_t W = 2 * D;                                 // +/- 2 chips (2 bins of offset)

    int rc = -1;
    kiss_fft_cpx* up = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* dn = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* C = (kiss_fft_cpx*)malloc(count * sizeof(kiss_fft_cpx));
    double* e = (double*)malloc((len + 1) * sizeof(double));
    float* pu = (float*)malloc(count * sizeof(float)); // |<z_m, up>|^2 / N
    float* pd = (float*)malloc(count * sizeof(float)); // |<z_m, down>|^2 / N
    float* U = NULL;
    float* Dn = NULL;
    float* Dp = NULL;
    if (!up || !dn || !C || !e || !pu || !pd) goto done;

    base_chirp(g, up, dn);
    e[0] = 0.0;
    for (size_t i = 0; i < len; i++)
        e[i + 1] = e[i] + (double)z[i].r * z[i].r + (double)z[i].i * z[i].i;
    double emax = 0.0;
    for (size_t m = 0; m < count; m++) {
        double E = e[m + N] - e[m];
        if (E > emax) emax = E;
    }
    if (!(emax > 0.0) || !isfinite(emax)) { rc = 0; goto done; } // silence / garbage
    const double gate = CSS_ENERGY_GATE * emax;

    for (int pass = 0; pass < 2; pass++) {
        float* pw = pass == 0 ? pu : pd;
        if (cxcorr(z, len, pass == 0 ? up : dn, N, C, count) != 0) goto done;
        for (size_t m = 0; m < count; m++) {
            double p = ((double)C[m].r * C[m].r + (double)C[m].i * C[m].i) / (double)N;
            pw[m] = p < (double)FLT_MAX ? (float)p : FLT_MAX; // NaN stays NaN
        }
    }
    free(C); C = NULL;

    U = (float*)malloc(nm * sizeof(float));
    Dn = (float*)malloc(nm * sizeof(float));
    Dp = (float*)malloc(nm * sizeof(float));
    if (!U || !Dn || !Dp) goto done;
    // Each slot is normalised by the mean window energy of all 10 slots, so a
    // slot holding only a fragment of signal (preamble cut by the buffer end,
    // a frame next to silence) cannot score like a whole chirp, and
    // rho = |<z, c>|^2 / (N * Ebar) <= 1 when the slots carry equal energy.
    for (size_t m = 0; m < nm; m++) {
        double su = 0.0;
        // m + 10N <= len and m + 9N < count by construction of nm; the
        // explicit check keeps that visible to static analysis.
        const size_t last = m + CSS_PREAMBLE_SYMBOLS * N;
        if (last > len || last - N >= count) {
            U[m] = Dn[m] = 0.0f;
            continue;
        }
        double ebar = (e[last] - e[m]) / CSS_PREAMBLE_SYMBOLS;
        if (!(ebar > gate)) {
            U[m] = Dn[m] = 0.0f;
            continue;
        }
        for (size_t i = 0; i < CSS_PREAMBLE_UP; i++) su += pu[m + i * N];
        // Both down slots must match (the weaker one counts): one symbol
        // early or late, one of them holds an up-chirp.
        float d0 = pd[m + CSS_PREAMBLE_UP * N], d1 = pd[m + (CSS_PREAMBLE_UP + 1) * N];
        U[m] = clamp_rho(su / (CSS_PREAMBLE_UP * ebar));
        Dn[m] = clamp_rho((double)(d0 < d1 ? d0 : d1) / ebar);
    }
    free(e); e = NULL;
    // Down-chirp metric pooled over +/- W: with an offset the two peaks are
    // up to 2W apart, and U alone already pins the timing to within W.
    if (sliding_max(Dn, nm, W, Dp) != 0) goto done;

    double theta = (isfinite(threshold) && threshold > 0.0f) ? (double)threshold : 3.0;
    double thr = theta * 4.0 / (double)g->M; // noise rho averages ~1 / (1.2 M)
    if (thr > 0.5) thr = 0.5;

    size_t m0 = nm;
    for (size_t m = 0; m < nm; m++) {
        if (U[m] >= thr && Dp[m] >= thr) { m0 = m; break; }
    }
    if (m0 == nm) { rc = 0; goto done; }

    // The first qualifying lag can sit on the rising edge of the peak; the
    // start maximises U + Dn within the next symbol.
    size_t hi = m0 + N + 4 * D;
    if (hi > nm) hi = nm;
    size_t ms = m0;
    for (size_t m = m0 + 1; m < hi; m++)
        if (U[m] + Dp[m] > U[ms] + Dp[ms]) ms = m;

    double tu = refine_peak(U, nm, ms, W);
    double td = refine_peak(Dn, nm, ms, W);
    double t0 = 0.5 * (tu + td);
    if (!isfinite(t0) || t0 < 0.0) t0 = 0.0;
    if (t0 > (double)(nm - 1)) t0 = (double)(nm - 1);
    double cfo = 0.5 * (td - tu) * g->B / (double)N;
    if (!isfinite(cfo)) cfo = 0.0;

    size_t ku = (size_t)(tu + 0.5), kd = (size_t)(td + 0.5);
    if (ku >= nm) ku = nm - 1;
    if (kd >= nm) kd = nm - 1;
    double rho = (CSS_PREAMBLE_UP * (double)U[ku] + CSS_PREAMBLE_DOWN * (double)Dn[kd]) /
                 CSS_PREAMBLE_SYMBOLS;
    if (rho < 1e-6) rho = 1e-6;
    if (rho > 1.0 - 1e-6) rho = 1.0 - 1e-6;

    res->start = t0;
    res->cfo_hz = cfo;
    res->rho = (float)rho;
    res->snr_db = (float)(10.0 * log10(rho / (1.0 - rho)));
    rc = 1;
done:
    free(up); free(dn); free(C); free(e);
    free(pu); free(pd); free(U); free(Dn); free(Dp);
    return rc;
}

int css_detect_frame(const float* samples, size_t len, const css_geometry_t* g,
                     float threshold, css_sync_result_t* res) {
    if (!samples || !g || !res || len > CSS_MAX_INPUT) return -1;
    if (len < CSS_PREAMBLE_SYMBOLS * (size_t)g->N) return 0;
    kiss_fft_cpx* z = css_baseband(samples, len, g);
    if (!z) return -1;
    int rc = css_sync_bb(z, len, g, threshold, res);
    free(z);
    return rc;
}

uint8_t* css_demodulate(const float* samples, size_t len, sw_config cfg, size_t* out_bytes) {
    if (out_bytes) *out_bytes = 0;
    css_geometry_t g;
    if (!samples || !out_bytes || len > CSS_MAX_INPUT || css_geometry(&cfg, &g) != 0)
        return NULL;
    const size_t N = (size_t)g.N, M = (size_t)g.M, D = (size_t)g.D;
    if (N == 0 || M == 0 || len < 2 || len < (CSS_PREAMBLE_SYMBOLS + 1) * N) return NULL;

    kiss_fft_cpx* z = css_baseband(samples, len, &g);
    if (!z) return NULL;
    css_sync_result_t sync;
    if (css_sync_bb(z, len, &g, cfg.threshold, &sync) != 1) {
        free(z);
        return NULL;
    }

    size_t data0 = (size_t)(sync.start + 0.5) + CSS_PREAMBLE_SYMBOLS * N;
    size_t nsym = data0 < len ? (len - data0) / N : 0;
    if (nsym == 0) {
        free(z);
        return NULL;
    }
    size_t nbits = nsym * (size_t)g.sf;
    size_t nbytes = (nbits + 7) / 8;

    uint8_t* out = (uint8_t*)calloc(nbytes, 1);
    kiss_fft_cpx* ref = (kiss_fft_cpx*)malloc(M * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* in = (kiss_fft_cpx*)malloc(M * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* Y = (kiss_fft_cpx*)malloc(M * sizeof(kiss_fft_cpx));
    kiss_fft_cfg fft = kiss_fft_alloc((int)M, 0, NULL, NULL);
    if (!out || !ref || !in || !Y || !fft) {
        free(out); free(ref); free(in); free(Y); free(fft); free(z);
        return NULL;
    }

    // Chip-rate base up-chirp c[m] = exp(j pi (m^2 / M - m)); store conj(c).
    for (size_t m = 0; m < M; m++) {
        double ph = 0.5 * ((double)m * (double)m / (double)M - (double)m);
        ph -= floor(ph);
        ref[m].r = (kiss_fft_scalar)cos(CSS_TWO_PI_D * ph);
        ref[m].i = (kiss_fft_scalar)(-sin(CSS_TWO_PI_D * ph));
    }

    const double first = sync.start + (double)(CSS_PREAMBLE_SYMBOLS * N);
    const double fstep = sync.cfo_hz / g.fs; // offset, cycles per sample
    size_t bit = 0;
    for (size_t s = 0; s < nsym; s++) {
        double base = first + (double)s * (double)N;
        for (size_t m = 0; m < M; m++) {
            double pos = base + (double)(m * D);
            double fl = floor(pos);
            size_t i0 = fl < 0.0 ? 0 : (size_t)fl;
            double a = pos - fl;
            if (i0 > len - 2) { i0 = len - 2; a = 1.0; }
            double vr = (1.0 - a) * z[i0].r + a * z[i0 + 1].r;
            double vi = (1.0 - a) * z[i0].i + a * z[i0 + 1].i;
            double ph = fmod(fstep * pos, 1.0);
            double cr = cos(CSS_TWO_PI_D * ph), ci = -sin(CSS_TWO_PI_D * ph);
            double wr = vr * cr - vi * ci, wi = vr * ci + vi * cr;
            in[m].r = to_scalar(wr * ref[m].r - wi * ref[m].i);
            in[m].i = to_scalar(wr * ref[m].i + wi * ref[m].r);
        }
        kiss_fft(fft, in, Y);
        size_t k = 0;
        double best = -1.0;
        for (size_t j = 0; j < M; j++) {
            double p = (double)Y[j].r * Y[j].r + (double)Y[j].i * Y[j].i;
            if (p > best) { best = p; k = j; }
        }
        unsigned v = (unsigned)(k ^ (k >> 1)); // Gray code of the symbol
        for (int b = g.sf - 1; b >= 0; b--, bit++) {
            if ((v >> b) & 1u) out[bit / 8] |= (uint8_t)(0x80u >> (bit % 8));
        }
    }

    free(ref); free(in); free(Y); free(fft); free(z);
    *out_bytes = nbytes;
    return out;
}

// ---------------------------------------------------------------------------
// Legacy single-chirp helpers (css_config_t)
// ---------------------------------------------------------------------------

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

    kiss_fft_cpx* fft_in = (kiss_fft_cpx*)malloc(N_fft * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* fft_out = (kiss_fft_cpx*)malloc(N_fft * sizeof(kiss_fft_cpx));
    if (!fft_in || !fft_out) {
        free(fft_in);
        free(fft_out);
        return 0;
    }

    for (int n = 0; n < N; n++) {
        fft_in[n].r = samples[n] * downchirp[n];
        fft_in[n].i = 0.0f;
    }
    for (int n = N; n < N_fft; n++) {
        fft_in[n].r = 0.0f;
        fft_in[n].i = 0.0f;
    }

    kiss_fft_cfg cfg = kiss_fft_alloc(N_fft, 0, NULL, NULL);
    if (!cfg) {
        free(fft_in);
        free(fft_out);
        return 0;
    }
    kiss_fft(cfg, fft_in, fft_out);

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

    double ratio = (double)k_peak * (double)N / (double)N_fft;
    int sym_value = (int)(ratio + 0.5);
    sym_value = (sym_value + (1 << SF)) % (1 << SF);

    free(fft_in);
    free(fft_out);
    free(cfg);
    return sym_value;
}
