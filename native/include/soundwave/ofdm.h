#ifndef SOUNDWAVE_OFDM_H
#define SOUNDWAVE_OFDM_H
// OFDM modem — constellation mapping, pilot insertion, IDFT, CP, and inverse.

#include <stddef.h>
#include <stdint.h>
#include "kiss_fft.h"

typedef struct {
    int num_subcarriers;  // FFT size (256, 512, 1024, 2048)
    int cp_length;        // Cyclic prefix length
    int num_pilots;       // Number of pilot subcarriers
    int pilot_spacing;    // Pilot insertion spacing
    int modulation;       // 0=BPSK, 1=QPSK, 2=16QAM
} ofdm_config_t;

void ofdm_init(ofdm_config_t* cfg);

// Map bits to constellation symbols (BPSK/QPSK/16QAM).
void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X);

// Insert known pilot symbols at pilot subcarrier indices.
void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X);

// IFFT + cyclic prefix (single OFDM symbol).
void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time);

// Full frame modulation (multiple OFDM symbols).
void ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len);

// DFT demodulation: remove CP, FFT, normalize.
void ofdm_dft_demodulate(const float* y, int N, int cp_length, kiss_fft_cpx* Y);

// Full frame demodulation (detect, FFT, equalize, demap).
uint8_t* ofdm_demodulate_frame(const float* samples, size_t len,
                                const ofdm_config_t* cfg, size_t* out_len);

#endif
