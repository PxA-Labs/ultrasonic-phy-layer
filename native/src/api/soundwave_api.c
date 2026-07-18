// C API dispatch layer: routes sw_*() calls to internal module implementations.
// All functions validate parameters and return sw_error_t codes.

#include "soundwave_api.h"
#include "soundwave/crc.h"
#include "soundwave/rs.h"
#include "soundwave/css.h"
#include "soundwave/ofdm.h"
#include "soundwave/sync.h"
#include "soundwave/audio.h"

SW_API const char* sw_version(void) { return SW_VERSION; }

SW_API int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc) {
    if (!data || !crc || len == 0) return SW_ERR_BAD_PARAM;
    *crc = crc32_compute(data, len);
    return SW_OK;
}

SW_API int sw_rs_encode(const uint8_t* data, size_t data_len,
                        uint8_t* parity, size_t* parity_len) {
    if (!data || !parity || !parity_len) return SW_ERR_BAD_PARAM;
    rs_encode(data, data_len, parity, 255);
    *parity_len = 255 - data_len;
    return SW_OK;
}

SW_API int sw_rs_decode(uint8_t* data, size_t* data_len,
                        const uint8_t* parity, size_t parity_len,
                        int* errors_corrected) {
    (void)data; (void)data_len; (void)parity; (void)parity_len; (void)errors_corrected;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len) {
    (void)bits; (void)bit_len; (void)cfg; (void)samples;
    *sample_len = 0;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_css_demodulate(const float* samples, size_t sample_len,
                             sw_config_t cfg, uint8_t* bits, size_t* bit_len) {
    (void)samples; (void)sample_len; (void)cfg; (void)bits;
    *bit_len = 0;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len,
                            sw_config_t cfg, float* samples, size_t* sample_len) {
    (void)bits; (void)bit_len; (void)cfg; (void)samples;
    *sample_len = 0;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_ofdm_demodulate(const float* samples, size_t sample_len,
                              sw_config_t cfg, uint8_t* bits, size_t* bit_len) {
    (void)samples; (void)sample_len; (void)cfg; (void)bits;
    *bit_len = 0;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr) {
    (void)samples; (void)len; (void)cfg;
    *frame_start = 0;
    *snr = 0.0f;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_estimate_cfo(const float* samples, size_t len,
                           sw_config_t cfg, float* cfo_hz) {
    (void)samples; (void)len; (void)cfg;
    *cfo_hz = 0.0f;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle) {
    (void)cfg; (void)handle;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_capture_stop(void* handle) {
    (void)handle;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_capture_read(void* handle, float* buffer,
                                 size_t count, size_t* read) {
    (void)handle; (void)buffer; (void)count;
    *read = 0;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_playback_start(sw_config_t cfg, void** handle) {
    (void)cfg; (void)handle;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_playback_stop(void* handle) {
    (void)handle;
    return SW_ERR_NOT_IMPLEMENTED;
}

SW_API int sw_audio_playback_write(void* handle, const float* buffer,
                                   size_t count) {
    (void)handle; (void)buffer; (void)count;
    return SW_ERR_NOT_IMPLEMENTED;
}
