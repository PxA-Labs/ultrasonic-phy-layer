#ifndef AWGN_UTIL_H
#define AWGN_UTIL_H

#include <stdlib.h>
#include <math.h>

// Box-Muller transform to generate zero-mean Gaussian distributed random noise with variance std_dev^2
static inline float awgn_generate_sample(float std_dev) {
    float u1 = (float)rand() / (float)RAND_MAX;
    float u2 = (float)rand() / (float)RAND_MAX;
    if (u1 < 1e-10f) u1 = 1e-10f; // avoid log(0)
    float z0 = sqrtf(-2.0f * logf(u1)) * cosf(6.283185307179586f * u2);
    return z0 * std_dev;
}

// Add AWGN to a signal to match a target SNR (in dB)
static inline void awgn_add_noise(const float* signal, size_t len, float snr_db, float* noisy_signal) {
    double sum_sq = 0.0;
    for (size_t i = 0; i < len; i++) {
        sum_sq += (double)signal[i] * (double)signal[i];
    }
    float signal_power = (float)(sum_sq / (double)len);
    if (signal_power < 1e-10f) signal_power = 1e-10f;
    float noise_power = signal_power / powf(10.0f, snr_db / 10.0f);
    float std_dev = sqrtf(noise_power);

    for (size_t i = 0; i < len; i++) {
        noisy_signal[i] = signal[i] + awgn_generate_sample(std_dev);
    }
}

#endif // AWGN_UTIL_H
