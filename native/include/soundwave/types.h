/**
 * @file types.h
 * @brief Shared data structures, status codes, and configuration types for Soundwave PHY.
 * 
 * @copyright Copyright (c) 2026 PxA Labs (Archit Mittal, Purvansh Joshi)
 * @license MIT License
 */

#ifndef SOUNDWAVE_TYPES_H
#define SOUNDWAVE_TYPES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Soundwave Physical Layer Modem Configuration.
 */
typedef struct {
    int    sample_rate;      /**< Audio sampling rate in Hz (default 44100 Hz). */
    int    modulation;       /**< Modulation scheme: 0 = CSS (Chirp Spread Spectrum), 1 = OFDM. */
    int    sf;               /**< CSS Spreading Factor (7 to 12). */
    int    num_subcarriers;  /**< OFDM FFT Size (256, 512, 1024, 2048). */
    int    cp_length;        /**< OFDM Cyclic Prefix length in samples. */
    int    num_pilots;       /**< OFDM Pilot subcarrier count for channel estimation. */
    float  coding_rate;      /**< Forward Error Correction (FEC) coding rate (0.5, 0.75). */
    float  threshold;        /**< Preamble detection threshold multiplier theta. */
    int    equalizer;        /**< Equalizer algorithm: 0 = Zero-Forcing (ZF), 1 = MMSE. */
} sw_config;

typedef sw_config sw_config_t;

/**
 * @brief Audio time-domain float signal container.
 */
typedef struct {
    float* data;            /**< Pointer to floating-point PCM audio samples. */
    size_t length;          /**< Number of audio samples in data array. */
    float  sample_rate;     /**< Sampling frequency in Hz. */
} sw_signal;

typedef sw_signal sw_signal_t;

/**
 * @brief Byte and bit buffer container.
 */
typedef struct {
    uint8_t* data;          /**< Pointer to raw byte/bit array. */
    size_t   length;        /**< Byte or bit count. */
} sw_buffer;

typedef sw_buffer sw_buffer_t;

/**
 * @brief Frequency-domain magnitude spectrum container for UI visualizers.
 */
typedef struct {
    float* magnitudes;     /**< Magnitude values per FFT frequency bin. */
    size_t num_bins;       /**< Number of frequency bins (e.g. 256, 512). */
    float  min_freq;       /**< Minimum frequency in Hz (e.g. 0.0 Hz). */
    float  max_freq;       /**< Maximum frequency in Hz (e.g. 22050.0 Hz). */
} sw_spectrum;

typedef sw_spectrum sw_spectrum_t;

/**
 * @brief Soundwave return status and error codes.
 */
typedef enum {
    SW_OK                  =  0,  /**< Operation completed successfully. */
    SW_ERR_BAD_PARAM       = -1,  /**< Invalid argument or null pointer. */
    SW_ERR_MEMORY          = -2,  /**< Out of memory allocation error. */
    SW_ERR_DECODE          = -3,  /**< RS/FEC decode error (> t errors). */
    SW_ERR_SYNC            = -4,  /**< Preamble detection or CFO sync failure. */
    SW_ERR_AUDIO           = -5,  /**< miniaudio device I/O error. */
    SW_ERR_NOT_IMPLEMENTED = -6   /**< Feature not implemented. */
} sw_error;

typedef sw_error sw_error_t;

#ifdef __cplusplus
}
#endif

#endif // SOUNDWAVE_TYPES_H
