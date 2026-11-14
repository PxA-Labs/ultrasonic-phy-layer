// OFDM demodulator: DFT, channel estimation, equalization, demapping.
// References: MATHEMATICAL_MODEL.md sections 3-4.

#include "soundwave/ofdm.h"
#include "soundwave/chanest.h"
#include "soundwave/equalizer.h"
#include "soundwave/cfo.h"
#include "soundwave/sync.h"
#include "soundwave/common.h"
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>

void ofdm_dft_demodulate(const float* y, int N, int cp_length, kiss_fft_cpx* Y) {
    if (!y || !Y || N <= 0 || cp_length < 0) return;
    kiss_fft_cpx* temp = (kiss_fft_cpx*)malloc((size_t)N * sizeof(kiss_fft_cpx));
    kiss_fft_cfg fft_cfg = kiss_fft_alloc(N, 0, NULL, NULL); // 0 = forward
    if (!temp || !fft_cfg) {
        memset(Y, 0, (size_t)N * sizeof(kiss_fft_cpx)); // no data on OOM
        free(temp);
        free(fft_cfg);
        return;
    }
    for (int n = 0; n < N; n++) {
        temp[n].r = y[cp_length + n];
        temp[n].i = 0.0f;
    }
    kiss_fft(fft_cfg, temp, Y);
    float norm = 1.0f / sqrtf((float)N);
    for (int n = 0; n < N; n++) {
        Y[n].r *= norm;
        Y[n].i *= norm;
    }
    free(temp);
    free(fft_cfg);
}

// Phase advance of the second preamble copy over the first,
// angle(sum_k conj(Y1[k]) Y2[k]) over the given subcarriers; 0 if undefined.
static float preamble_phase_advance(const kiss_fft_cpx* Y1, const kiss_fft_cpx* Y2,
                                    const int* idx, int n) {
    double re = 0.0, im = 0.0;
    for (int i = 0; i < n; i++) {
        int k = idx[i];
        re += (double)Y1[k].r * Y2[k].r + (double)Y1[k].i * Y2[k].i;
        im += (double)Y1[k].r * Y2[k].i - (double)Y1[k].i * Y2[k].r;
    }
    double a = atan2(im, re);
    return isfinite(a) ? (float)a : 0.0f;
}

// Phase-slope statistics of the two preamble copies starting at `start`:
// with H_k = Y_k conj(X_k) (|X_k| = 1) on the active bins, D_k =
// H_{k+1} conj(H_k). *acc = sum D_k (its phase is the slope 2 pi s / N of the
// cyclic shift s between FFT window and symbol body), *mag = sum |D_k|.
// |acc| / mag is ~1 for the real preamble (channel smooth across adjacent
// bins) and ~1/sqrt(num_active) for anything else. Returns 0 if out of range.
static int preamble_slope(const float* samples, size_t len, size_t start, int N, int cp,
                          const ofdm_layout_t* lay, const kiss_fft_cpx* X, kiss_fft_cpx* Y,
                          double* acc_r, double* acc_i, double* mag) {
    size_t L = (size_t)N + (size_t)cp;
    *acc_r = *acc_i = *mag = 0.0;
    if (start >= len || len - start < 2 * L) return 0;
    int b = OFDM_TIMING_BACKOFF(cp);
    for (int copy = 0; copy < 2; copy++) {
        ofdm_dft_demodulate(samples + start + (size_t)copy * L, N, cp - b, Y);
        double pr = 0.0, pi = 0.0;
        for (int k = lay->first_bin; k <= lay->last_bin; k++) {
            double hr = (double)Y[k].r * X[k].r + (double)Y[k].i * X[k].i;
            double hi = (double)Y[k].i * X[k].r - (double)Y[k].r * X[k].i;
            if (k > lay->first_bin) {
                double dr = hr * pr + hi * pi;
                double di = hi * pr - hr * pi;
                *acc_r += dr;
                *acc_i += di;
                *mag += sqrt(dr * dr + di * di);
            }
            pr = hr;
            pi = hi;
        }
    }
    return isfinite(*acc_r) && isfinite(*acc_i) && isfinite(*mag);
}

static size_t refine_with(const float* samples, size_t len, size_t frame_start, int N,
                          int cp, const ofdm_layout_t* lay, const kiss_fft_cpx* X,
                          kiss_fft_cpx* Y) {
    size_t L = (size_t)N + (size_t)cp;
    size_t start = frame_start;
    for (int pass = 0; pass < 2; pass++) {
        double ar, ai, mag;
        if (!preamble_slope(samples, len, start, N, cp, lay, X, Y, &ar, &ai, &mag)) break;
        if (!(ar * ar + ai * ai > 0.0)) break;
        double s = atan2(ai, ar) * (double)N / (2.0 * (double)SW_PI);
        double e = s + (double)OFDM_TIMING_BACKOFF(cp); // detected - true start
        if (!isfinite(e) || fabs(e) >= 0.5 * (double)L) break;
        long shift = lround(e);
        if (shift == 0) break;
        if (shift > 0) {
            start = (size_t)shift > start ? 0 : start - (size_t)shift;
        } else {
            start += (size_t)(-shift);
        }
    }
    return start;
}

static double preamble_score(const float* samples, size_t len, size_t start, int N, int cp,
                             const ofdm_layout_t* lay, const kiss_fft_cpx* X,
                             kiss_fft_cpx* Y) {
    double ar, ai, mag;
    if (!preamble_slope(samples, len, start, N, cp, lay, X, Y, &ar, &ai, &mag) ||
        !(mag > 0.0))
        return 0.0;
    return sqrt(ar * ar + ai * ai) / mag;
}

size_t ofdm_refine_timing(const float* samples, size_t len, size_t frame_start,
                          int N, int cp, const ofdm_layout_t* lay) {
    if (!samples || !lay || N <= 0 || cp < 0 || lay->num_active < 2) return frame_start;
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    kiss_fft_cpx* Y = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    size_t start = frame_start;
    if (X && Y && ofdm_preamble_spectrum(lay, N, cp, X) == SW_OK)
        start = refine_with(samples, len, frame_start, N, cp, lay, X, Y);
    free(X);
    free(Y);
    return start;
}

int ofdm_locate_preamble(const float* samples, size_t len, int N, int cp,
                         const ofdm_layout_t* lay, float threshold, int allow_fallback,
                         size_t* frame_start, float* snr) {
    if (!samples || !lay || !frame_start || !snr || N <= 0 || cp < 0 || cp > N ||
        lay->num_active < 2)
        return 0;
    *frame_start = 0;
    *snr = 0.0f;
    size_t L = (size_t)N + (size_t)cp;
    if (len < 2 * L) return 0;

    int found = 0;
    size_t n_pos = len - 2 * L + 1; // candidate starts m: [m, m + 2L) in range
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    kiss_fft_cpx* Y = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    float* tmpl = (float*)calloc(L, sizeof(float));
    float* R = (float*)malloc((len - L + 1) * sizeof(float));
    double* cum = (double*)malloc((len + 1) * sizeof(double));
    if (!X || !Y || !tmpl || !R || !cum || ofdm_preamble_spectrum(lay, N, cp, X) != SW_OK)
        goto done;

    // 1. Schmidl-Cox repetition metric (sync_frame.c): presence gate and
    // fallback position.
    sync_config_t sc;
    memset(&sc, 0, sizeof sc);
    sc.mode = 1;
    sc.threshold = threshold;
    sc.zc_root = 1;
    sc.zc_length = lay->num_active;
    sc.matched_filter_len = (int)L;
    size_t sc_start = 0;
    float sc_snr = 0.0f;
    int sc_ok = sync_detect_frame(samples, len, &sc, &sc_start, &sc_snr);
    if (!sc_ok && !allow_fallback) goto done;
    if (sc_ok) {
        *frame_start = refine_with(samples, len, sc_start, N, cp, lay, X, Y);
        *snr = sc_snr;
        found = 1;
    }

    // 2. Normalised matched filter on the known two-copy preamble:
    //    rho(m) = (R[m] + R[m + L]) / sqrt(2 E_t E_y(m)),
    // R = correlation with one preamble copy, E_t its energy, E_y the
    // energy of y[m .. m + 2L). Unlike the repetition metric it ignores two
    // identical data symbols and is level-independent. The earliest strong
    // peak wins (a buffer may hold several frames; the first is wanted), and
    // a candidate must also pass the phase-slope preamble check.
    {
        ofdm_config_t oc;
        memset(&oc, 0, sizeof oc);
        oc.num_subcarriers = N;
        oc.cp_length = cp;
        ofdm_modulate_symbol(&oc, X, tmpl);
        if (sync_xcorr_fft(samples, len, tmpl, L, R) != 0) goto done;
        double et = 0.0;
        for (size_t n = 0; n < L; n++) et += (double)tmpl[n] * tmpl[n];
        cum[0] = 0.0;
        for (size_t n = 0; n < len; n++) cum[n + 1] = cum[n] + (double)samples[n] * samples[n];
        double ey_max = 0.0;
        for (size_t m = 0; m < n_pos; m++) {
            double ey = cum[m + 2 * L] - cum[m];
            if (ey > ey_max) ey_max = ey;
        }
        if (!(et > 0.0) || !(ey_max > 0.0) || !isfinite(ey_max)) goto done;
        const double ey_floor = 1e-4 * ey_max; // -40 dB: silence cannot win
        // rho is stored in R[m] (R[m + L] is read before R[m + L] is
        // overwritten: m only grows).
        double rho_max = 0.0;
        size_t rho_arg = 0;
        for (size_t m = 0; m < n_pos; m++) {
            double ey = cum[m + 2 * L] - cum[m];
            double rho = ey > ey_floor ? ((double)R[m] + (double)R[m + L]) / sqrt(2.0 * et * ey)
                                       : 0.0;
            if (!isfinite(rho)) rho = 0.0;
            R[m] = (float)rho;
            if (rho > rho_max) {
                rho_max = rho;
                rho_arg = m;
            }
        }
        double tau = 0.75 * rho_max;
        if (tau < 0.3) tau = 0.3;
        size_t pick = SIZE_MAX;
        double pick_rho = 0.0;
        int tries = 0;
        for (size_t m = 0; m < n_pos && tries < 8; m++) {
            if (R[m] < tau) continue;
            size_t end = m + L / 2 < n_pos ? m + L / 2 : n_pos;
            size_t best = m;
            for (size_t j = m; j < end; j++)
                if (R[j] > R[best]) best = j;
            tries++;
            size_t s = refine_with(samples, len, best, N, cp, lay, X, Y);
            if (preamble_score(samples, len, s, N, cp, lay, X, Y) >= OFDM_PREAMBLE_MIN_SCORE) {
                pick = s;
                pick_rho = R[best];
                break;
            }
            m = end; // continue after this peak
        }
        if (pick == SIZE_MAX && !found && rho_max > 0.0) {
            pick = refine_with(samples, len, rho_arg, N, cp, lay, X, Y);
            pick_rho = rho_max;
        }
        if (pick != SIZE_MAX) {
            *frame_start = pick;
            double r = pick_rho < 0.999 ? pick_rho : 0.999;
            if (!found) *snr = (float)(10.0 * log10(r * r / (1.0 - r * r) + 1e-12));
            found = 1;
        }
    }

done:
    free(X);
    free(Y);
    free(tmpl);
    free(R);
    free(cum);
    return found;
}

int ofdm_demodulate(const float* samples, size_t len, sw_config cfg, uint8_t** decoded, size_t* out_len) {
    return ofdm_demodulate_ex(samples, len, cfg, decoded, out_len, NULL, 0, NULL);
}

int ofdm_demodulate_ex(const float* samples, size_t len, sw_config cfg,
                       uint8_t** decoded, size_t* out_len,
                       kiss_fft_cpx* eq_out, size_t eq_cap, size_t* eq_count) {
    if (eq_count) *eq_count = 0;
    if (!samples || !decoded || !out_len) {
        if (out_len) *out_len = 0;
        return SW_ERR_BAD_PARAM;
    }
    *decoded = NULL;
    *out_len = 0;

    int ret_code = SW_OK;

    // Apply defaults to cfg (carrier_freq / bandwidth: ofdm_layout_compute)
    if (cfg.sample_rate <= 0) cfg.sample_rate = 44100;
    if (cfg.num_subcarriers <= 0) cfg.num_subcarriers = 256;
    if (cfg.cp_length <= 0) cfg.cp_length = cfg.num_subcarriers / 8;
    if (cfg.num_pilots <= 0) cfg.num_pilots = cfg.num_subcarriers / 16;
    if (cfg.threshold <= 0.0f) cfg.threshold = 3.0f;

    int N = cfg.num_subcarriers;
    int cp = cfg.cp_length;
    // Internal callers bypass sw_config_validate(): enforce the invariants the
    // index arithmetic below relies on (power-of-two FFT, CP within a symbol).
    if (N < 16 || N > 4096 || (N & (N - 1)) != 0 || cp < 0 || cp > N)
        return SW_ERR_BAD_PARAM;
    float fs = (float)cfg.sample_rate;
    int modulation = cfg.ofdm_modulation; // 0 = BPSK, 1 = QPSK

    // Allocate pointers to NULL for safe single-label cleanup
    int* data_indices = NULL;
    int* pilot_indices = NULL;
    kiss_fft_cpx* X_pre = NULL;
    float* analytic_real = NULL;
    float* analytic_imag = NULL;
    float* corrected = NULL;
    kiss_fft_cpx* Y_pre1 = NULL;
    kiss_fft_cpx* Y_pre2 = NULL;
    kiss_fft_cpx* Y_pre = NULL;
    int* active_indices = NULL;
    kiss_fft_cpx* X_active = NULL;
    kiss_fft_cpx* H_active = NULL;
    kiss_fft_cpx* H = NULL;
    kiss_fft_cpx* Y_sym = NULL;
    kiss_fft_cpx* X_hat = NULL;
    uint8_t* temp_bits = NULL;
    uint8_t* decoded_buf = NULL;

    // Subcarrier allocation: the same band plan as the transmitter
    // (ofdm_layout_compute); every bin outside it is ignored.
    ofdm_layout_t lay;
    if (ofdm_layout_compute(N, (float)cfg.sample_rate, cfg.carrier_freq,
                            cfg.bandwidth, &lay) != SW_OK) {
        ret_code = SW_ERR_BAD_PARAM;
        goto cleanup;
    }
    int num_data = lay.num_data;
    int N_active = lay.num_active;
    int active_start = lay.first_bin;
    data_indices = (int*)calloc((size_t)num_data, sizeof(int));
    pilot_indices = (int*)calloc((size_t)lay.num_pilots, sizeof(int));
    if (!data_indices || !pilot_indices) {
        ret_code = SW_ERR_MEMORY;
        goto cleanup;
    }
    ofdm_allocate_subcarriers(&lay, data_indices, pilot_indices);

    // 1. Preamble ZC-OFDM frequency-domain template X_pre (active bins only)
    X_pre = (kiss_fft_cpx*)calloc(N, sizeof(kiss_fft_cpx));
    if (!X_pre) {
        ret_code = SW_ERR_MEMORY;
        goto cleanup;
    }
    ret_code = ofdm_preamble_spectrum(&lay, N, cp, X_pre);
    if (ret_code != SW_OK) goto cleanup;

    // 2. Timing synchronization / preamble detection: Schmidl-Cox metric,
    // fine timing from the preamble phase slope (MATHEMATICAL_MODEL.md 3.2),
    // verified against the known preamble with a matched-filter fallback.
    size_t frame_start = 0;
    float detected_snr = 0.0f;
    if (!ofdm_locate_preamble(samples, len, N, cp, &lay, cfg.threshold, 1,
                              &frame_start, &detected_snr)) {
        ret_code = SW_ERR_SYNC;
        goto cleanup;
    }

    // 4. Timing backoff, CFO estimation & correction
    // Need the two preamble symbols plus at least one data symbol after
    // frame_start; otherwise the reads below run past the sample buffer and
    // num_symbols underflows into a huge allocation.
    size_t sym_len = (size_t)N + (size_t)cp;
    if (frame_start >= len || len - frame_start < 3 * sym_len) {
        ret_code = SW_ERR_SYNC;
        goto cleanup;
    }
    size_t payload_len = len - frame_start;

    // FFT window placement (MATHEMATICAL_MODEL.md section 4.0): every symbol
    // -- both preamble copies and all data symbols -- is sampled
    // OFDM_TIMING_BACKOFF(cp) samples early, inside its cyclic prefix. An
    // early window is a cyclic shift, i.e. the same linear phase ramp
    // e^{-j 2 pi k b / N} on every symbol, which the preamble channel
    // estimate absorbs exactly. A late window instead mixes in the next
    // symbol's CP (ISI): the Schmidl-Cox peak can land a sample or two late,
    // and a window one sample late already costs ~20 % EVM. The first
    // OFDM_WOLA_LEN(cp) samples of each symbol carry the transmit window's
    // cross-fade, so the receiver is ISI-free for timing errors in
    // [-(cp - b - OFDM_WOLA_LEN(cp)), +b].
    int fft_offset = cp - OFDM_TIMING_BACKOFF(cp);

    analytic_real = (float*)malloc(payload_len * sizeof(float));
    analytic_imag = (float*)malloc(payload_len * sizeof(float));
    corrected = (float*)malloc(payload_len * sizeof(float));
    Y_pre1 = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    Y_pre2 = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    Y_pre = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    active_indices = (int*)malloc(N_active * sizeof(int));
    X_active = (kiss_fft_cpx*)malloc(N_active * sizeof(kiss_fft_cpx));
    H_active = (kiss_fft_cpx*)malloc(N_active * sizeof(kiss_fft_cpx));
    H = (kiss_fft_cpx*)malloc(N * sizeof(kiss_fft_cpx));
    if (!analytic_real || !analytic_imag || !corrected || !Y_pre1 || !Y_pre2 ||
        !Y_pre || !active_indices || !X_active || !H_active || !H) {
        ret_code = SW_ERR_MEMORY;
        goto cleanup;
    }
    for (int i = 0; i < N_active; i++) {
        active_indices[i] = active_start + i;
        X_active[i] = X_pre[active_start + i];
    }
    if (sync_real_to_analytic(samples + frame_start, payload_len, analytic_real, analytic_imag) != 0) {
        ret_code = SW_ERR_MEMORY;
        goto cleanup;
    }

    // Schmidl-Cox CFO in the frequency domain (MATHEMATICAL_MODEL.md 3.3):
    // the second preamble copy is the first delayed by sym_len samples, so on
    // every active subcarrier Y2[k] = Y1[k] e^{j 2 pi cfo sym_len / fs}. Using
    // the same backed-off FFT windows as the channel estimate keeps both
    // windows inside the repeated preamble for any timing error the receiver
    // tolerates, so a noiseless frame yields exactly cfo = 0. (A time-domain
    // correlation over the full sym_len window spans |timing error| samples
    // outside the repetition and turned a few samples of timing error into a
    // spurious CFO.) The real signal's mirror image leaks into the band in
    // proportion to the offset, so a second pass re-estimates the residual
    // after the first correction, where that leakage is negligible.
    float cfo = 0.0f;
    const float* cfo_src = samples + frame_start;
    for (int pass = 0; pass < 2; pass++) {
        ofdm_dft_demodulate(cfo_src, N, fft_offset, Y_pre1);
        ofdm_dft_demodulate(cfo_src + sym_len, N, fft_offset, Y_pre2);
        float dphi = preamble_phase_advance(Y_pre1, Y_pre2, active_indices, N_active);
        cfo += fs / (SW_TWO_PI * (float)sym_len) * dphi;
        sync_apply_cfo_correction(analytic_real, analytic_imag, payload_len, cfo, fs, corrected);
        cfo_src = corrected;
    }

    // Free analytic buffers early as they are no longer needed
    free(analytic_real); analytic_real = NULL;
    free(analytic_imag); analytic_imag = NULL;

    // 5. Channel Estimation using preamble
    ofdm_dft_demodulate(corrected, N, fft_offset, Y_pre1);
    ofdm_dft_demodulate(corrected + sym_len, N, fft_offset, Y_pre2);

    for (int k = 0; k < N; k++) {
        Y_pre[k].r = 0.5f * (Y_pre1[k].r + Y_pre2[k].r);
        Y_pre[k].i = 0.5f * (Y_pre1[k].i + Y_pre2[k].i);
    }

    // Perform Least-Squares (LS) estimation on active positions
    chanest_ls(Y_pre, X_active, active_indices, N_active, H_active);

    // Interpolate channel across all subcarriers (size N)
    chanest_linear_interp(H_active, active_indices, N_active, N, H);

    // MMSE regularisation sigma_n^2 / sigma_x^2 (eq. 22). Data symbols are
    // unit-energy (sigma_x^2 = 1), and the noise variance per subcarrier comes
    // from the two identical preamble copies (their difference is pure
    // noise). The preamble carries ZC values, not the +/-1 data-symbol pilots,
    // so a pilot-based estimate against +/-1 would read the preamble itself as
    // noise (~0 dB SNR) and shrink every MMSE point by ~3x.
    // Garbage input can make this non-finite (libFuzzer + UBSan, issue #28):
    // clamp to the regularisation ceiling.
    float inv_snr = chanest_noise_var_repeated(Y_pre1, Y_pre2, active_indices, N_active);
    if (!(inv_snr >= 0.0f && inv_snr <= 10.0f)) inv_snr = 10.0f;

    // 6. Demodulate, Equalize & Demap each data symbol
    // Data symbol s (0-based) is demodulated when its FFT window
    // [(2+s) L + cp - b, (2+s) L + cp - b + N) lies inside the input, i.e.
    // payload_len >= (3+s) L - b. Every such symbol is returned (trailing
    // noise too; the frame codec finds the frame length). A buffer that ends
    // exactly at the frame's last sample -- or up to b samples earlier, as
    // after a late detection -- therefore yields all of the frame's symbols,
    // and the cp/2 fade-out tail (< L - b) never adds a symbol.
    // payload_len >= 3 * sym_len (checked above).
    size_t b_off = (size_t)OFDM_TIMING_BACKOFF(cp);
    int num_symbols = (int)((payload_len + b_off) / sym_len) - 2;
    if (num_symbols <= 0) {
        ret_code = SW_ERR_SYNC;
        goto cleanup;
    }

    int bits_per_symbol = num_data * (modulation == 0 ? 1 : 2);
    size_t total_allocated_bytes = ((size_t)num_symbols * (size_t)bits_per_symbol + 7) / 8;
    decoded_buf = (uint8_t*)calloc(total_allocated_bytes, sizeof(uint8_t));

    Y_sym = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    X_hat = (kiss_fft_cpx*)malloc(num_data * sizeof(kiss_fft_cpx));
    temp_bits = (uint8_t*)malloc(((bits_per_symbol + 7) / 8) * sizeof(uint8_t));

    if (!decoded_buf || !Y_sym || !X_hat || !temp_bits) {
        ret_code = SW_ERR_MEMORY;
        goto cleanup;
    }

    size_t total_bits_demodulated = 0;

    for (int s = 0; s < num_symbols; s++) {
        // DFT Demodulation
        float* sym_src = corrected + ((size_t)2 + (size_t)s) * ((size_t)N + (size_t)cp);
        ofdm_dft_demodulate(sym_src, N, fft_offset, Y_sym);

        // Common phase error from the pilots (MATHEMATICAL_MODEL.md 4.2):
        // theta = angle(sum_p Y[k_p] conj(H[k_p] X_p)), X_p = +1, -1, +1, ...
        // The channel estimate comes from the preamble only, so residual CFO
        // (and slow drift) would otherwise rotate every later symbol a little
        // more; with ~10 active bins the CFO estimate is too coarse to hold
        // the phase over a long frame without this.
        {
            double cr = 0.0, ci = 0.0;
            for (int p = 0; p < lay.num_pilots; p++) {
                int k = pilot_indices[p];
                double sgn = (p % 2 == 0) ? 1.0 : -1.0;
                cr += sgn * ((double)Y_sym[k].r * H[k].r + (double)Y_sym[k].i * H[k].i);
                ci += sgn * ((double)Y_sym[k].i * H[k].r - (double)Y_sym[k].r * H[k].i);
            }
            double mag = sqrt(cr * cr + ci * ci);
            if (mag > 0.0 && isfinite(mag)) {
                float c = (float)(cr / mag), sn = (float)(-ci / mag); // e^{-j theta}
                for (int k = lay.first_bin; k <= lay.last_bin; k++) {
                    float yr = Y_sym[k].r, yi = Y_sym[k].i;
                    Y_sym[k].r = yr * c - yi * sn;
                    Y_sym[k].i = yr * sn + yi * c;
                }
            }
        }

        // Equalization
        if (cfg.equalizer == 1) {
            equalize_mmse(Y_sym, H, data_indices, num_data, inv_snr, X_hat);
        } else {
            equalize_zf(Y_sym, H, data_indices, num_data, X_hat);
        }

        // Optional copy of the equalized data-subcarrier points (constellation
        // diagram, EVM). Bounded by the caller's capacity.
        if (eq_out && eq_count) {
            for (int d = 0; d < num_data && *eq_count < eq_cap; d++) {
                eq_out[*eq_count] = X_hat[d];
                (*eq_count)++;
            }
        }

        // Hard Demapping
        size_t bits_decoded = 0;
        demap_data(X_hat, num_data, modulation, temp_bits, &bits_decoded);

        // Append bits to final decoded array
        for (size_t b = 0; b < bits_decoded; b++) {
            int bit_val = (temp_bits[b / 8] >> (7 - (b % 8))) & 1;
            if (total_bits_demodulated % 8 == 0) {
                decoded_buf[total_bits_demodulated / 8] = 0;
            }
            decoded_buf[total_bits_demodulated / 8] |= (bit_val << (7 - (total_bits_demodulated % 8)));
            total_bits_demodulated++;
        }
    }

    // Undo the transmitter's data whitening (ofdm_scramble is self-inverse).
    ofdm_scramble(decoded_buf, total_bits_demodulated);

    *decoded = decoded_buf;
    *out_len = total_bits_demodulated;
    ret_code = SW_OK;

cleanup:
    free(data_indices);
    free(pilot_indices);
    free(X_pre);
    free(analytic_real);
    free(analytic_imag);
    free(corrected);
    free(Y_pre1);
    free(Y_pre2);
    free(Y_pre);
    free(active_indices);
    free(X_active);
    free(H_active);
    free(H);
    free(Y_sym);
    free(X_hat);
    free(temp_bits);
    if (ret_code != SW_OK) {
        free(decoded_buf);
    }
    return ret_code;
}

int ofdm_demodulate_frame(const float* samples, size_t len,
                          const ofdm_config_t* cfg, uint8_t** decoded, size_t* out_len) {
    if (!samples || !cfg || !decoded || !out_len) {
        if (out_len) *out_len = 0;
        return SW_ERR_BAD_PARAM;
    }
    *decoded = NULL;
    *out_len = 0;

    sw_config_t sw_cfg;
    memset(&sw_cfg, 0, sizeof sw_cfg);
    sw_cfg.sample_rate = cfg->sample_rate > 0.0f ? (int)lroundf(cfg->sample_rate) : 44100;
    sw_cfg.modulation = 1; // OFDM
    sw_cfg.sf = 8;
    sw_cfg.num_subcarriers = cfg->num_subcarriers;
    sw_cfg.cp_length = cfg->cp_length;
    sw_cfg.num_pilots = cfg->num_pilots;
    sw_cfg.coding_rate = 0.5f;
    sw_cfg.threshold = 3.0f;
    sw_cfg.equalizer = 0;
    sw_cfg.carrier_freq = cfg->carrier_freq; // 0 = default band
    sw_cfg.bandwidth = cfg->bandwidth;
    sw_cfg.symbol_duration = 0.02f;
    sw_cfg.amplitude = 0.8f;
    sw_cfg.ofdm_modulation = cfg->modulation;

    size_t out_bits = 0;
    uint8_t* decoded_bits = NULL;
    int ret = ofdm_demodulate(samples, len, sw_cfg, &decoded_bits, &out_bits);
    if (ret != SW_OK) {
        return ret;
    }
    *decoded = decoded_bits;
    *out_len = out_bits; // return bit count consistently!
    return SW_OK;
}
