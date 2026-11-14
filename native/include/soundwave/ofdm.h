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
    int num_pilots;       // Number of pilot subcarriers (informational)
    int pilot_spacing;    // Pilot insertion spacing (informational; see OFDM_PILOT_SPACING)
    float pilot_boost;    // Pilot amplitude boost factor
    int modulation;       // 0=BPSK, 1=QPSK
    // Occupied band (MATHEMATICAL_MODEL.md 2.2.2). 0 selects the default.
    float sample_rate;    // Hz (default 44100)
    float carrier_freq;   // band centre in Hz (default 19000)
    float bandwidth;      // band width in Hz (default 2000)
} ofdm_config_t;

// --- Ultrasonic band plan ----------------------------------------------------
//
// Active (data + pilot) subcarriers are confined to the configured band
// [carrier_freq - bandwidth/2, carrier_freq + bandwidth/2]. Every other bin --
// DC, the whole audible range, the Nyquist bin and their Hermitian mirrors --
// is zero, on TX and RX alike. OFDM_EDGE_GUARD_BINS bins at each band edge
// also stay empty so that the main lobe of the outermost subcarriers does not
// spill past the band edge.
#define OFDM_DEFAULT_SAMPLE_RATE  44100.0f
#define OFDM_DEFAULT_CARRIER_HZ   19000.0f
#define OFDM_DEFAULT_BANDWIDTH_HZ 2000.0f
#define OFDM_EDGE_GUARD_BINS      1
#define OFDM_MIN_ACTIVE_BINS      4   // >= 1 pilot + 3 data subcarriers
#define OFDM_PILOT_SPACING        8   // every 8th active bin, starting with the first

// Transmit windowing (WOLA): each symbol's first OFDM_WOLA_LEN(cp) samples
// (inside its cyclic prefix) rise with a raised-cosine ramp while the
// previous symbol's cyclic suffix of the same length fades out over them.
// This removes the symbol-boundary discontinuities whose sinc sidelobes would
// otherwise put audible energy below 16 kHz. The receiver's FFT window starts
// OFDM_TIMING_BACKOFF(cp) before the end of the CP, i.e. after the ramp, so
// windowing costs no throughput; the frame is OFDM_WOLA_LEN(cp) samples
// longer (the last symbol's fade-out). The junction between the two preamble
// copies is not windowed so that they stay sample-identical (Schmidl-Cox).
#define OFDM_WOLA_LEN(cp) ((cp) / 2)

typedef struct {
    int first_bin;   // lowest active subcarrier index k (f = k * fs / N)
    int last_bin;    // highest active subcarrier index
    int num_active;  // last_bin - first_bin + 1
    int num_pilots;  // ceil(num_active / OFDM_PILOT_SPACING)
    int num_data;    // num_active - num_pilots
} ofdm_layout_t;

// Computes the active-subcarrier layout of the band
// [carrier - bw/2, carrier + bw/2] for an N-point FFT at sample_rate.
// Zero sample_rate / carrier_freq / bandwidth select the defaults above.
// Returns SW_ERR_BAD_PARAM if N is not a power of two in 16..4096, any value
// is non-finite or negative, the band does not lie in (0, fs/2 - fs/N]
// (one subcarrier of guard below Nyquist), or fewer than
// OFDM_MIN_ACTIVE_BINS subcarriers fit. *out is zeroed on error.
int ofdm_layout_compute(int N, float sample_rate, float carrier_freq,
                        float bandwidth, ofdm_layout_t* out);

// Same, from an ofdm_config_t (num_subcarriers <= 0 selects 256).
int ofdm_layout_from_config(const ofdm_config_t* cfg, ofdm_layout_t* out);

void ofdm_init(ofdm_config_t* cfg);

// BPSK Constellation mapping
void bpsk_map(int bit, kiss_fft_cpx* out);
int bpsk_demap(kiss_fft_cpx symbol);

// QPSK Constellation mapping
void qpsk_map(uint8_t dibit, kiss_fft_cpx* out);
uint8_t qpsk_demap_hard(kiss_fft_cpx symbol);

// Subcarrier allocation inside the active band: every OFDM_PILOT_SPACING-th
// active bin (starting with first_bin) is a pilot, the rest carry data. Writes
// lay->num_data data indices and lay->num_pilots pilot indices (ascending).
// Only the positive-frequency bins are listed; ofdm_modulate_symbol() mirrors
// them into the conjugate-symmetric negative bins. All other bins are null.
void ofdm_allocate_subcarriers(const ofdm_layout_t* lay, int* data_indices,
                               int* pilot_indices);

// Frequency-domain preamble: a Zadoff-Chu sequence (root 1) of length
// lay->num_active on the active bins, zero elsewhere, times a common phase
// chosen so that the un-windowed junction between the two preamble copies
// (cyclic prefix length cp) is continuous. X holds N bins.
// Returns SW_OK, or SW_ERR_MEMORY / SW_ERR_BAD_PARAM.
int ofdm_preamble_spectrum(const ofdm_layout_t* lay, int N, int cp, kiss_fft_cpx* X);

// Map bits to the data subcarriers of the configured band (BPSK/QPSK).
void ofdm_map_constellation(const ofdm_config_t* cfg, const uint8_t* bits,
                            size_t bit_len, kiss_fft_cpx* X);

// Insert known pilot symbols at pilot subcarrier indices.
void ofdm_insert_pilots(const ofdm_config_t* cfg, kiss_fft_cpx* X);

// IFFT + cyclic prefix (single OFDM symbol).
void ofdm_modulate_symbol(const ofdm_config_t* cfg, const kiss_fft_cpx* X,
                          float* time);

// Full frame modulation: two identical preamble symbols, then
// ceil(bit_len / bits_per_symbol) data symbols, each N + cp samples, plus the
// OFDM_WOLA_LEN(cp)-sample fade-out of the last symbol:
//   (2 + num_symbols) * (N + cp) + OFDM_WOLA_LEN(cp) samples.
// Returns SW_OK, SW_ERR_BAD_PARAM (invalid FFT size / CP / band) or
// SW_ERR_OVERFLOW (*sample_len then holds the required size).
int ofdm_modulate_frame(const ofdm_config_t* cfg, const uint8_t* bits,
                         size_t bit_len, float* samples, size_t* sample_len);

// Full frame modulation returning sw_signal
sw_signal ofdm_modulate(const uint8_t* bits, size_t num_bits, sw_config cfg);

// Receiver timing backoff b: the FFT window of every symbol starts b samples
// before the end of its cyclic prefix (offset cp - b). The first
// OFDM_WOLA_LEN(cp) samples of a symbol hold the transmit window's overlap,
// so detection errors in [-(cp - b - OFDM_WOLA_LEN(cp)), +b] samples stay
// ISI-free (+-cp/4 for the defaults). See MATHEMATICAL_MODEL.md 4.0.
#define OFDM_TIMING_BACKOFF(cp) ((cp) / 4)

// Fine timing. frame_start is a coarse estimate of the frame's first sample
// (start of the first preamble copy). The preamble channel estimate of an
// FFT window that is s samples off the symbol body is the channel times
// e^{j 2 pi k s / N}; its phase slope across the active bins gives the
// detection error, which is removed (rounded to whole samples, two passes).
// Returns the refined start, or frame_start if it cannot be refined.
size_t ofdm_refine_timing(const float* samples, size_t len, size_t frame_start,
                          int N, int cp, const ofdm_layout_t* lay);

// DFT demodulation: skip cp_length samples (the FFT window offset), FFT, normalize.
void ofdm_dft_demodulate(const float* y, int N, int cp_length, kiss_fft_cpx* Y);

// Full frame demodulation (detect, FFT, equalize, demap). Returns SW_OK or error.
int ofdm_demodulate_frame(const float* samples, size_t len,
                          const ofdm_config_t* cfg, uint8_t** decoded, size_t* out_len);

// Top-level demodulation. Returns SW_OK or error.
int ofdm_demodulate(const float* samples, size_t len, sw_config cfg, uint8_t** decoded, size_t* out_len);

// Same as ofdm_demodulate, and additionally copies up to eq_cap equalized
// data-subcarrier points (symbol-major, data-subcarrier order) into eq_out;
// *eq_count receives the number written. eq_out/eq_count may be NULL.
int ofdm_demodulate_ex(const float* samples, size_t len, sw_config cfg,
                       uint8_t** decoded, size_t* out_len,
                       kiss_fft_cpx* eq_out, size_t eq_cap, size_t* eq_count);

#endif
