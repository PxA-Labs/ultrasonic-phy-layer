#ifndef SOUNDWAVE_OFDM_H
#define SOUNDWAVE_OFDM_H
// OFDM modem — constellation mapping, pilot insertion, IDFT, CP, and inverse.

#include <stddef.h>
#include <stdint.h>
#include "kiss_fft.h"
#include "soundwave/types.h"

typedef struct {
    int num_subcarriers;  // FFT size (256, 512, 1024, 2048)
    int cp_length;        // Cyclic prefix length
    int num_pilots;       // Number of pilot subcarriers
    int pilot_spacing;    // Pilot insertion spacing
    float pilot_boost;    // Pilot amplitude boost factor
    int modulation;       // 0=BPSK, 1=QPSK, 2=16QAM
} ofdm_config_t;

void ofdm_init(ofdm_config_t* cfg);

// BPSK Constellation mapping
void bpsk_map(int bit, kiss_fft_cpx* out);
int bpsk_demap(kiss_fft_cpx symbol);

// QPSK Constellation mapping
void qpsk_map(uint8_t dibit, kiss_fft_cpx* out);
uint8_t qpsk_demap_hard(kiss_fft_cpx symbol);

// Subcarrier allocation
/**
 * @brief Allocates subcarriers for OFDM.
 * 
 * Note: The third parameter null_indices contains both true nulls (DC, guard bands, middle null)
 * and the dependent/conjugate symmetric subcarriers in the negative frequencies. The positive
 * active data and pilot symbols are mirrored into these conjugate bins to ensure a real-valued
 * time-domain signal. Demodulators/equalizers should only process the positive frequencies
 * returned in data_indices and pilot_indices.
 */
void ofdm_allocate_subcarriers(int N, int* data_indices, int* pilot_indices, int* null_indices,
                               int* num_data, int* num_pilots, int* num_nulls);

// Map bits to constellation symbols (BPSK/QPSK/16QAM).
void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X);

// Insert known pilot symbols at pilot subcarrier indices.
void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X);

// IFFT + cyclic prefix (single OFDM symbol).
void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time);

// Full frame modulation (multiple OFDM symbols). Returns SW_OK or error.
int ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len);

// Full frame modulation returning sw_signal
sw_signal ofdm_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg);

// DFT demodulation: remove CP, FFT, normalize.
void ofdm_dft_demodulate(const float* y, int N, int cp_length, kiss_fft_cpx* Y);

// Full frame demodulation (detect, FFT, equalize, demap). Returns SW_OK or error.
int ofdm_demodulate_frame(const float* samples, size_t len,
                          const ofdm_config_t* cfg, uint8_t** decoded, size_t* out_len);

// Top-level demodulation. Returns SW_OK or error.
int ofdm_demodulate(const float* samples, size_t len, sw_config cfg, uint8_t** decoded, size_t* out_len);

#endif
