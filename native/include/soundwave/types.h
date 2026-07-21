// Shared data types for Soundwave PHY layer.

#ifndef SOUNDWAVE_TYPES_H
#define SOUNDWAVE_TYPES_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Modem configuration structure
typedef struct {
    int    sample_rate;      // Hz (default 44100)
    int    modulation;       // 0=CSS, 1=OFDM
    int    sf;               // CSS spreading factor 7..12
    int    num_subcarriers;  // OFDM FFT size (256, 512, 1024, 2048)
    int    cp_length;        // OFDM cyclic prefix length
    int    num_pilots;       // OFDM pilot subcarrier count
    float  coding_rate;      // FEC coding rate (0.5, 0.75)
    float  threshold;        // Preamble detection threshold theta
    int    equalizer;        // 0=Zero-Forcing, 1=MMSE
} sw_config;

typedef sw_config sw_config_t;

// Audio / time-domain signal buffer
typedef struct {
    float* data;
    size_t length;
    float  sample_rate;
} sw_signal;

typedef sw_signal sw_signal_t;

// Byte / bit buffer
typedef struct {
    uint8_t* data;
    size_t   length;
} sw_buffer;

typedef sw_buffer sw_buffer_t;

// Frequency-domain spectrum buffer
typedef struct {
    float* magnitudes;
    size_t num_bins;
    float  min_freq;
    float  max_freq;
} sw_spectrum;

typedef sw_spectrum sw_spectrum_t;

// Soundwave error codes
typedef enum {
    SW_OK                  =  0,
    SW_ERR_BAD_PARAM       = -1,
    SW_ERR_MEMORY          = -2,
    SW_ERR_DECODE          = -3,
    SW_ERR_SYNC            = -4,
    SW_ERR_AUDIO           = -5,
    SW_ERR_NOT_IMPLEMENTED   = -6,
} sw_error;

typedef sw_error sw_error_t;

#ifdef __cplusplus
}
#endif

#endif // SOUNDWAVE_TYPES_H
