// FFT-based sliding cross-correlation (overlap-save).
//
// R[m] = sum_{n=0}^{s_len-1} y[m + n] * s[n],   m = 0 .. y_len - s_len
//
// The direct form costs O(y_len * s_len): for CSS sync at 96 kHz with 50 ms
// chirps (s_len = 4800) over a 0.9 M-sample frame that is ~8.6e9 MACs per
// template (a fuzzer-found 40 s hang in issue #28, and seconds per RX decode
// attempt in the app). Overlap-save brings it to O(y_len * log s_len).
//
// Correlation is convolution with the time-reversed template. With an FFT of
// size nfft >= 2*s_len, each block of nfft input samples yields
// L = nfft - s_len + 1 valid outputs.

#include "soundwave/sync.h"
#include "kiss_fftr.h"
#include <stdlib.h>
#include <string.h>

static size_t next_pow2(size_t v) {
    size_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

int sync_xcorr_fft(const float* y, size_t y_len,
                   const float* s, size_t s_len, float* R) {
    if (!y || !s || !R || s_len == 0 || y_len < s_len) return -1;

    size_t nfft = next_pow2(2 * s_len);
    if (nfft < 1024) nfft = 1024;
    if (nfft > (size_t)1 << 26) return -1; // absurd template length
    size_t nbins = nfft / 2 + 1;
    size_t step = nfft - s_len + 1;
    size_t out_len = y_len - s_len + 1;

    int rc = -1;
    kiss_fftr_cfg fwd = kiss_fftr_alloc((int)nfft, 0, NULL, NULL);
    kiss_fftr_cfg inv = kiss_fftr_alloc((int)nfft, 1, NULL, NULL);
    kiss_fft_scalar* buf = (kiss_fft_scalar*)malloc(nfft * sizeof(kiss_fft_scalar));
    kiss_fft_cpx* H = (kiss_fft_cpx*)malloc(nbins * sizeof(kiss_fft_cpx));
    kiss_fft_cpx* X = (kiss_fft_cpx*)malloc(nbins * sizeof(kiss_fft_cpx));
    if (!fwd || !inv || !buf || !H || !X) goto done;

    // H = FFT(time-reversed template, zero-padded to nfft)
    memset(buf, 0, nfft * sizeof(kiss_fft_scalar));
    for (size_t k = 0; k < s_len; k++) buf[k] = s[s_len - 1 - k];
    kiss_fftr(fwd, buf, H);

    const float scale = 1.0f / (float)nfft;
    for (size_t p = 0; p < out_len; p += step) {
        // Input block y[p .. p + nfft), zero-padded past the end.
        size_t avail = y_len - p;
        size_t take = avail < nfft ? avail : nfft;
        memcpy(buf, y + p, take * sizeof(float));
        if (take < nfft) memset(buf + take, 0, (nfft - take) * sizeof(float));

        kiss_fftr(fwd, buf, X);
        for (size_t k = 0; k < nbins; k++) {
            float xr = X[k].r, xi = X[k].i;
            X[k].r = xr * H[k].r - xi * H[k].i;
            X[k].i = xr * H[k].i + xi * H[k].r;
        }
        kiss_fftri(inv, X, buf);

        // Circular-conv index k >= s_len - 1 is alias-free and maps to
        // R[p + k - (s_len - 1)].
        size_t count = out_len - p < step ? out_len - p : step;
        for (size_t j = 0; j < count; j++) R[p + j] = buf[s_len - 1 + j] * scale;
    }
    rc = 0;
done:
    free(buf); free(H); free(X);
    kiss_fftr_free(fwd); kiss_fftr_free(inv);
    return rc;
}

int sync_xcorr_power_fft(const float* y, size_t y_len,
                         const float* s, size_t s_len,
                         float* power, size_t count) {
    if (!power || s_len == 0 || y_len < s_len || count > y_len - s_len + 1) return -1;
    float* R = (float*)malloc((y_len - s_len + 1) * sizeof(float));
    if (!R) return -1;
    int rc = sync_xcorr_fft(y, y_len, s, s_len, R);
    if (rc == 0) {
        for (size_t m = 0; m < count; m++) power[m] = R[m] * R[m];
    }
    free(R);
    return rc;
}
