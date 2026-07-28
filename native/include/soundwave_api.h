/**
 * @file soundwave_api.h
 * @brief Public C API for the Soundwave Ultrasonic Physical Layer (PHY) library.
 * 
 * This header defines the stable C ABI callable from Flutter via dart:ffi or from
 * any host language (C/C++, Rust, Python, Go). All functions use strict C linkage
 * with fixed-width C-compatible types.
 * 
 * @copyright Copyright (c) 2026 PxA Labs (Archit Mittal, Purvansh Joshi)
 * @license MIT License
 */

#ifndef SOUNDWAVE_API_H
#define SOUNDWAVE_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(SW_BUILD_DLL)
    #define SW_API __declspec(dllexport)
#elif defined(_MSC_VER)
    #define SW_API
#else
    #define SW_API __attribute__((visibility("default")))
#endif

#define SW_VERSION "1.0.0"

#include "soundwave/types.h"

// --- Version Information ---

/**
 * @brief Returns the library semantic version string.
 * @return Const pointer to version string (e.g. "1.0.0").
 */
SW_API const char* sw_version(void);

// --- CRC-32 Checksum ---

/**
 * @brief Computes IEEE 802.3 CRC-32 checksum over input data bytes.
 * @param data Pointer to input data buffer.
 * @param len Byte length of data buffer.
 * @param crc Output pointer receiving 32-bit CRC checksum.
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc);

// --- Reed-Solomon Error Correction ---

/**
 * @brief Encodes input data using Reed-Solomon RS(255,223) FEC over GF(2^8).
 * @param data Pointer to input message bytes (K <= 223).
 * @param data_len Byte length of input message.
 * @param parity Pre-allocated buffer receiving 32 parity bytes.
 * @param parity_len Output pointer filled with written parity length (32).
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_rs_encode(const uint8_t* data, size_t data_len,
                        uint8_t* parity, size_t* parity_len);

/**
 * @brief Decodes Reed-Solomon codeword and corrects up to t=16 symbol errors in-place.
 * @param data Pointer to message data buffer (corrected in-place).
 * @param data_len Pointer to message byte length.
 * @param parity Pointer to parity bytes buffer (32 bytes).
 * @param parity_len Byte length of parity buffer.
 * @param errors_corrected Output pointer receiving number of corrected errors (0 to 16).
 * @return SW_OK (0) on success, SW_ERR_DECODE_FAILED if uncorrectable (>16 errors).
 */
SW_API int sw_rs_decode(uint8_t* data, size_t* data_len,
                        const uint8_t* parity, size_t parity_len,
                        int* errors_corrected);

// --- Chirp Spread Spectrum (CSS) Modem ---

/**
 * @brief Modulates bit array into Linear Frequency Modulated (LFM) chirp audio samples.
 * @param bits Pointer to input bit stream array.
 * @param bit_len Number of input bits.
 * @param cfg PHY configuration struct.
 * @param samples Pre-allocated output float sample buffer.
 * @param sample_len Input: capacity, Output: written sample count.
 * @return SW_OK (0) on success, or SW_ERR_OVERFLOW if sample buffer too small.
 */
SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len);

/**
 * @brief Demodulates LFM chirp audio samples into bit stream using dechirp and FFT.
 * @param samples Pointer to input float PCM audio samples.
 * @param sample_len Number of input audio samples.
 * @param cfg PHY configuration struct.
 * @param bits Pre-allocated output bit buffer.
 * @param bit_len Input: capacity, Output: demodulated bit count.
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_css_demodulate(const float* samples, size_t sample_len,
                             sw_config_t cfg, uint8_t* bits, size_t* bit_len);

// --- OFDM Modem ---

/**
 * @brief Modulates bit array into OFDM acoustic audio samples (IDFT + Cyclic Prefix).
 * @param bits Pointer to input bit stream array.
 * @param bit_len Number of input bits.
 * @param cfg PHY configuration struct.
 * @param samples Pre-allocated output float sample buffer.
 * @param sample_len Input: capacity, Output: written sample count.
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len,
                            sw_config_t cfg, float* samples, size_t* sample_len);

/**
 * @brief Demodulates OFDM audio samples using DFT, LS channel estimation & equalization.
 * @param samples Pointer to input float PCM audio samples.
 * @param sample_len Number of input audio samples.
 * @param cfg PHY configuration struct.
 * @param bits Pre-allocated output bit buffer.
 * @param bit_len Input: capacity, Output: demodulated bit count.
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_ofdm_demodulate(const float* samples, size_t sample_len,
                              sw_config_t cfg, uint8_t* bits, size_t* bit_len);

// --- Synchronization & CFO ---

/**
 * @brief Detects preamble start offset using matched filter (CSS) or Zadoff-Chu correlation (OFDM).
 * @param samples Pointer to audio PCM sample buffer.
 * @param len Sample count.
 * @param cfg PHY configuration struct.
 * @param frame_start Output pointer receiving sample offset of preamble peak.
 * @param snr Output pointer receiving estimated Signal-to-Noise Ratio (dB).
 * @return SW_OK (0) if detected, SW_ERR_NOT_FOUND if peak below noise threshold.
 */
SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr);

/**
 * @brief Estimates Carrier Frequency Offset (CFO) in Hz using Schmidl-Cox preamble correlation.
 * @param samples Pointer to audio PCM sample buffer.
 * @param len Sample count.
 * @param cfg PHY configuration struct.
 * @param cfo_hz Output pointer receiving estimated CFO in Hz.
 * @return SW_OK (0) on success, or negative sw_error_t code.
 */
SW_API int sw_estimate_cfo(const float* samples, size_t len,
                           sw_config_t cfg, float* cfo_hz);

// --- Real-Time Audio I/O ---

/**
 * @brief Starts miniaudio real-time microphone capture stream at 44.1 kHz PCM.
 * @param cfg PHY configuration struct.
 * @param handle Output pointer receiving opaque audio handle.
 * @return SW_OK (0) on success, or SW_ERR_AUDIO_IO.
 */
SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle);

/**
 * @brief Stops real-time audio capture stream and releases device resources.
 * @param handle Opaque audio handle created by sw_audio_capture_start.
 * @return SW_OK (0) on success.
 */
SW_API int sw_audio_capture_stop(void* handle);

/**
 * @brief Reads captured PCM audio samples from ring buffer into caller array.
 * @param handle Opaque audio capture handle.
 * @param buffer Pre-allocated output float sample buffer.
 * @param count Number of samples requested.
 * @param read Output pointer receiving actual samples read.
 * @return SW_OK (0) on success.
 */
SW_API int sw_audio_capture_read(void* handle, float* buffer,
                                 size_t count, size_t* read);

/**
 * @brief Starts miniaudio real-time speaker playback stream at 44.1 kHz PCM.
 * @param cfg PHY configuration struct.
 * @param handle Output pointer receiving opaque audio handle.
 * @return SW_OK (0) on success, or SW_ERR_AUDIO_IO.
 */
SW_API int sw_audio_playback_start(sw_config_t cfg, void** handle);

/**
 * @brief Stops real-time audio playback stream and releases device resources.
 * @param handle Opaque audio handle.
 * @return SW_OK (0) on success.
 */
SW_API int sw_audio_playback_stop(void* handle);

/**
 * @brief Writes PCM audio samples into ring buffer for speaker playback.
 * @param handle Opaque audio playback handle.
 * @param buffer Pointer to float PCM audio samples.
 * @param count Number of samples to write.
 * @return SW_OK (0) on success.
 */
SW_API int sw_audio_playback_write(void* handle, const float* buffer,
                                   size_t count);

#ifdef __cplusplus
}
#endif

#endif // SOUNDWAVE_API_H
