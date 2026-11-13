// Automatic Gain Control — see include/soundwave/agc.h and
// docs/MATHEMATICAL_MODEL.md section 6.
//
//   p[n]   = p[n-1] + a_rms * (x[n]^2 - p[n-1])           (power estimate)
//   g_d[n] = clamp(target / sqrt(p[n] + eps), g_min, g_max)
//   g[n]   = g[n-1] + a * (g_d[n] - g[n-1]),  a = a_att if g_d < g else a_rel
//   g[n]   = min(g[n], peak_limit / |x[n]|)                (peak guard)
//   y[n]   = g[n] * x[n]
//   a_k    = 1 - exp(-1 / (tau_k * fs))

#include "soundwave/agc.h"
#include <math.h>
#include <stdlib.h>

#define AGC_EPS 1e-12f

struct agc_state {
    float target;
    float a_rms, a_att, a_rel;
    float power;  // running mean of x^2
    float gain;   // current linear gain
};

static float one_pole(float tau_s, float fs) {
    return 1.0f - expf(-1.0f / (tau_s * fs));
}

agc_state_t* agc_create(float sample_rate, float target_rms) {
    if (!isfinite(sample_rate) || sample_rate < 8000.0f || sample_rate > 192000.0f)
        return NULL;
    if (!isfinite(target_rms) || target_rms <= 0.0f || target_rms > 1.0f) return NULL;
    agc_state_t* agc = (agc_state_t*)calloc(1, sizeof(*agc));
    if (!agc) return NULL;
    agc->target = target_rms;
    agc->a_rms = one_pole(AGC_RMS_TAU_S, sample_rate);
    agc->a_att = one_pole(AGC_ATTACK_TAU_S, sample_rate);
    agc->a_rel = one_pole(AGC_RELEASE_TAU_S, sample_rate);
    agc_reset(agc);
    return agc;
}

void agc_destroy(agc_state_t* agc) { free(agc); }

void agc_reset(agc_state_t* agc) {
    if (!agc) return;
    // Start as if the input were already at the target level: unity gain.
    agc->power = agc->target * agc->target;
    agc->gain = 1.0f;
}

int agc_process(agc_state_t* agc, float* samples, size_t len) {
    if (!agc || (!samples && len > 0)) return -1;
    float p = agc->power, g = agc->gain;
    for (size_t n = 0; n < len; n++) {
        float x = samples[n];
        if (!isfinite(x)) {
            samples[n] = 0.0f; // drop, keep state untouched
            continue;
        }
        p += agc->a_rms * (x * x - p);
        float gd = agc->target / sqrtf(p + AGC_EPS);
        if (gd < AGC_MIN_GAIN) gd = AGC_MIN_GAIN;
        if (gd > AGC_MAX_GAIN) gd = AGC_MAX_GAIN;
        g += (gd < g ? agc->a_att : agc->a_rel) * (gd - g);
        float ax = fabsf(x);
        if (ax * g > AGC_PEAK_LIMIT) g = AGC_PEAK_LIMIT / ax; // instant on peaks
        if (g < AGC_MIN_GAIN) g = AGC_MIN_GAIN;
        float y = g * x;
        // A sample louder than peak_limit / g_min still has to fit in range.
        if (y > AGC_PEAK_LIMIT) y = AGC_PEAK_LIMIT;
        if (y < -AGC_PEAK_LIMIT) y = -AGC_PEAK_LIMIT;
        samples[n] = y;
    }
    agc->power = p;
    agc->gain = g;
    return 0;
}

float agc_gain(const agc_state_t* agc) { return agc ? agc->gain : 1.0f; }

float agc_gain_db(const agc_state_t* agc) { return 20.0f * log10f(agc_gain(agc)); }
