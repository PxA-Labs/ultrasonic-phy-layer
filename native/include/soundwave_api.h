// Public C API for the Soundwave DSP library.
// Callable from Flutter via dart:ffi. All functions are extern "C"
// with C-compatible types only (no C++ ABI). Buffer ownership:
// caller allocates, callee fills.

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

// Modem configuration, mirrored in Dart as SwConfig struct
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
} sw_config_t;

// Error codes
typedef enum {
    SW_OK                =  0,
    SW_ERR_BAD_PARAM     = -1,
    SW_ERR_MEMORY        = -2,
    SW_ERR_DECODE        = -3,
    SW_ERR_SYNC          = -4,
    SW_ERR_AUDIO         = -5,
    SW_ERR_NOT_IMPLEMENTED = -6,
} sw_error_t;

// --- Version ---
SW_API const char* sw_version(void);

// --- CRC-32 ---
SW_API int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc);

// --- Reed-Solomon ---
SW_API int sw_rs_encode(const uint8_t* data, size_t data_len,
                        uint8_t* parity, size_t* parity_len);
SW_API int sw_rs_decode(uint8_t* data, size_t* data_len,
                        const uint8_t* parity, size_t parity_len,
                        int* errors_corrected);

// --- CSS Modem ---
SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len);
SW_API int sw_css_demodulate(const float* samples, size_t sample_len,
                             sw_config_t cfg, uint8_t* bits, size_t* bit_len);

// --- OFDM Modem ---
SW_API int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len,
                            sw_config_t cfg, float* samples, size_t* sample_len);
SW_API int sw_ofdm_demodulate(const float* samples, size_t sample_len,
                              sw_config_t cfg, uint8_t* bits, size_t* bit_len);

// --- Synchronization ---
SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr);
SW_API int sw_estimate_cfo(const float* samples, size_t len,
                           sw_config_t cfg, float* cfo_hz);

// --- Audio I/O ---
SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle);
SW_API int sw_audio_capture_stop(void* handle);
SW_API int sw_audio_capture_read(void* handle, float* buffer,
                                 size_t count, size_t* read);
SW_API int sw_audio_playback_start(sw_config_t cfg, void** handle);
SW_API int sw_audio_playback_stop(void* handle);
SW_API int sw_audio_playback_write(void* handle, const float* buffer,
                                   size_t count);

#ifdef __cplusplus
}
#endif

#endif // SOUNDWAVE_API_H
