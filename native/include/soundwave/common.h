// Common types and utilities shared across all DSP modules.

#ifndef SOUNDWAVE_COMMON_H
#define SOUNDWAVE_COMMON_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

// Minimum positive float (used for divide-by-zero guards)
#define SW_EPSILON 1e-12f

// Pi constants
#define SW_PI      3.14159265358979323846f
#define SW_TWO_PI  6.28318530717958647693f

// Clamp value to [lo, hi]
#define SW_CLAMP(x, lo, hi) (((x) < (lo)) ? (lo) : (((x) > (hi)) ? (hi) : (x)))

// Maximum supported frame sizes
#define SW_MAX_PAYLOAD_BYTES  256
#define SW_MAX_SAMPLE_RATE    48000
#define SW_MIN_SAMPLE_RATE    8000

// Modulation modes (matches sw_config_t.modulation)
typedef enum {
    SW_MOD_CSS  = 0,
    SW_MOD_OFDM = 1,
} sw_modulation_t;

// Equalizer types (matches sw_config_t.equalizer)
typedef enum {
    SW_EQ_ZF   = 0,
    SW_EQ_MMSE = 1,
} sw_equalizer_t;

#endif // SOUNDWAVE_COMMON_H
