// Test helper: recovers the gain g that the OFDM modulator's per-frame peak
// normalization applied to a frame from sw_ofdm_modulate().
//
// The second preamble copy, samples [L, 2L) with L = N + cp, is neither
// windowed nor overlapped by a neighbouring symbol, so it is exactly g times
// the unscaled preamble symbol (ofdm_preamble_spectrum + ofdm_modulate_symbol,
// whose subcarriers have unit magnitude). The least-squares ratio gives g.
// Tests that reason about absolute levels (noise per subcarrier relative to
// unit-energy constellation points) use it to reference noise to the
// transmitted level; the frame's raw (pre-normalization) peak is amp / g.

#ifndef OFDM_GAIN_UTIL_H
#define OFDM_GAIN_UTIL_H

#include "soundwave_api.h"
#include "soundwave/ofdm.h"
#include <stdlib.h>
#include <string.h>

// Returns g, or 0 if it cannot be computed.
static double ofdm_frame_gain(const float* tx, size_t tx_len, sw_config_t cfg) {
    ofdm_config_t oc;
    memset(&oc, 0, sizeof oc);
    oc.num_subcarriers = cfg.num_subcarriers;
    oc.cp_length = cfg.cp_length;
    oc.modulation = cfg.ofdm_modulation;
    oc.sample_rate = cfg.sample_rate > 0 ? (float)cfg.sample_rate : 0.0f;
    oc.carrier_freq = cfg.carrier_freq;
    oc.bandwidth = cfg.bandwidth;
    ofdm_init(&oc);
    int N = oc.num_subcarriers, cp = oc.cp_length;
    size_t L = (size_t)N + (size_t)cp;
    if (tx_len < 2 * L) return 0.0;

    ofdm_layout_t lay;
    if (ofdm_layout_from_config(&oc, &lay) != SW_OK) return 0.0;
    kiss_fft_cpx* X = (kiss_fft_cpx*)calloc((size_t)N, sizeof(kiss_fft_cpx));
    float* sym = (float*)calloc(L, sizeof(float));
    double g = 0.0;
    if (X && sym && ofdm_preamble_spectrum(&lay, N, cp, X) == SW_OK) {
        ofdm_modulate_symbol(&oc, X, sym);
        double num = 0.0, den = 0.0;
        for (size_t n = 0; n < L; n++) {
            num += (double)tx[L + n] * (double)sym[n];
            den += (double)sym[n] * (double)sym[n];
        }
        if (den > 0.0) g = num / den;
    }
    free(X);
    free(sym);
    return g;
}

#endif // OFDM_GAIN_UTIL_H
