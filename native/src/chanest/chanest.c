// LS channel estimation and linear interpolation across subcarriers.
// References: MATHEMATICAL_MODEL.md equations 19-20.

#include "soundwave/chanest.h"
#include <math.h>

void chanest_ls(const kiss_fft_cpx* Y, const kiss_fft_cpx* X_p,
                const int* pilot_indices, int num_pilots, kiss_fft_cpx* H_p) {
    for (int i = 0; i < num_pilots; i++) {
        float mag2 = X_p[i].r * X_p[i].r + X_p[i].i * X_p[i].i;
        if (mag2 > 1e-10f) {
            float inv = 1.0f / mag2;
            H_p[i].r = (Y[pilot_indices[i]].r * X_p[i].r
                      + Y[pilot_indices[i]].i * X_p[i].i) * inv;
            H_p[i].i = (Y[pilot_indices[i]].i * X_p[i].r
                      - Y[pilot_indices[i]].r * X_p[i].i) * inv;
        } else {
            H_p[i].r = H_p[i].i = 0.0f;
        }
    }
}

void chanest_linear_interp(const kiss_fft_cpx* H_p, const int* pilot_indices,
                           int num_pilots, int N, kiss_fft_cpx* H) {
    for (int k = 0; k < N; k++) {
        if (k <= pilot_indices[0]) {
            H[k] = H_p[0];
        } else if (k >= pilot_indices[num_pilots - 1]) {
            H[k] = H_p[num_pilots - 1];
        } else {
            // Find surrounding pilots
            int p_left = 0, p_right = num_pilots - 1;
            for (int i = 0; i < num_pilots - 1; i++) {
                if (k >= pilot_indices[i] && k <= pilot_indices[i + 1]) {
                    p_left = i; p_right = i + 1; break;
                }
            }
            float frac = (float)(k - pilot_indices[p_left])
                       / (float)(pilot_indices[p_right] - pilot_indices[p_left]);
            H[k].r = H_p[p_left].r + frac * (H_p[p_right].r - H_p[p_left].r);
            H[k].i = H_p[p_left].i + frac * (H_p[p_right].i - H_p[p_left].i);
        }
    }
}

float chanest_estimate_snr(const kiss_fft_cpx* Y, const kiss_fft_cpx* X_p,
                           const kiss_fft_cpx* H_p, int num_pilots) {
    double P_signal = 0.0, P_noise = 0.0;
    for (int i = 0; i < num_pilots; i++) {
        float yr = Y[i].r, yi = Y[i].i;
        float hr = H_p[i].r, hi = H_p[i].i;
        float xr = X_p[i].r, xi = X_p[i].i;
        P_signal += (double)(hr * hr + hi * hi) * (double)(xr * xr + xi * xi);
        float err_r = yr - (hr * xr - hi * xi);
        float err_i = yi - (hr * xi + hi * xr);
        P_noise += (double)(err_r * err_r + err_i * err_i);
    }
    if (P_noise < 1e-12) return 100.0f;
    return 10.0f * log10f((float)(P_signal / P_noise));
}
