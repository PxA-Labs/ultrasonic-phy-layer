// Automatic Gain Control (AGC) for the RX pipeline (issue #92).
// Normalises microphone level before frame detection and demodulation.
// Equations: docs/MATHEMATICAL_MODEL.md section 6.

#ifndef SOUNDWAVE_AGC_H
#define SOUNDWAVE_AGC_H

#include <stddef.h>

#define AGC_DEFAULT_TARGET_RMS 0.25f   // -12 dBFS
#define AGC_MIN_GAIN           0.1f    // -20 dB
#define AGC_MAX_GAIN           40.0f   // +32 dB
#define AGC_RMS_TAU_S          0.010f  // 10 ms power estimate
#define AGC_ATTACK_TAU_S       0.001f  // 1 ms (gain decreasing)
#define AGC_RELEASE_TAU_S      0.100f  // 100 ms (gain increasing)
#define AGC_PEAK_LIMIT         1.0f    // |output| never exceeds full scale

typedef struct agc_state agc_state_t;

// Returns NULL for an invalid sample rate (outside 8..192 kHz) or target
// (not in (0, 1]), or on allocation failure.
agc_state_t* agc_create(float sample_rate, float target_rms);
void         agc_destroy(agc_state_t* agc);
void         agc_reset(agc_state_t* agc);

// Processes samples in place. Non-finite samples are output as 0 and do not
// disturb the state. Returns 0, or -1 on bad arguments.
int          agc_process(agc_state_t* agc, float* samples, size_t len);

float        agc_gain(const agc_state_t* agc);     // linear, [0.1, 40]
float        agc_gain_db(const agc_state_t* agc);  // 20*log10(gain)

#endif // SOUNDWAVE_AGC_H
