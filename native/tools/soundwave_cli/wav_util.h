#ifndef WAV_UTIL_H
#define WAV_UTIL_H

#include <stddef.h>
#include <stdint.h>

/**
 * @brief Write float audio samples to a 16-bit PCM mono WAV file.
 * @param filename Target file path.
 * @param samples Array of float samples in range [-1.0, 1.0].
 * @param num_samples Number of samples to write.
 * @param sample_rate Sampling rate in Hz.
 * @return 0 on success, -1 on failure.
 */
int wav_write_mono_i16(const char* filename, const float* samples, size_t num_samples, uint32_t sample_rate);

/**
 * @brief Read audio samples from a WAV file and convert to float mono samples.
 * @param filename Source file path.
 * @param out_samples Output pointer receiving dynamically allocated float samples array.
 * @param out_num_samples Output pointer receiving the number of samples read.
 * @param out_sample_rate Output pointer receiving the sampling rate in Hz.
 * @return 0 on success, -1 on failure.
 */
int wav_read_mono(const char* filename, float** out_samples, size_t* out_num_samples, uint32_t* out_sample_rate);

#endif // WAV_UTIL_H
