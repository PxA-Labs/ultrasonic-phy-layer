// C API dispatch layer: routes sw_*() calls to internal module implementations.
// All functions validate parameters and return sw_error_t codes.

#include "soundwave_api.h"
#include "soundwave/crc.h"
#include "soundwave/rs.h"
#include "soundwave/css.h"
#include "soundwave/ofdm.h"
#include "soundwave/sync.h"
#include "soundwave/cfo.h"
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
    if (!data || !data_len || !parity || !errors_corrected) return SW_ERR_BAD_PARAM;
    size_t k = *data_len;
    size_t n = k + parity_len;
    if (n > 255 || k == 0) return SW_ERR_BAD_PARAM;

    uint8_t r[256];
    memcpy(r, data, k);
    memcpy(r + k, parity, parity_len);

    int errs = rs_decode(r, n);
    if (errs < 0) {
        return SW_ERR_DECODE;
    }

    memcpy(data, r, k);
    *errors_corrected = errs;
    return SW_OK;
}

SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len) {
    if (!bits || !samples || !sample_len) return SW_ERR_BAD_PARAM;

    sw_signal sig = css_modulate(bits, bit_len, cfg);
    if (!sig.data) return SW_ERR_MEMORY;

    if (sig.length > *sample_len) {
        *sample_len = sig.length;
        free(sig.data);
        return SW_ERR_OVERFLOW;
    }

    memcpy(samples, sig.data, sig.length * sizeof(float));
    *sample_len = sig.length;
    free(sig.data);
    return SW_OK;
}

SW_API int sw_css_demodulate(const float* samples, size_t sample_len,
                             sw_config_t cfg, uint8_t* bits, size_t* bit_len) {
    if (!samples || !bits || !bit_len) return SW_ERR_BAD_PARAM;

    size_t out_bytes = 0;
    uint8_t* decoded = css_demodulate(samples, sample_len, cfg, &out_bytes);
    if (!decoded) {
        *bit_len = 0;
        return SW_ERR_SYNC;
    }

    size_t decoded_bits = out_bytes * 8;
    if (decoded_bits > *bit_len) {
        *bit_len = decoded_bits;
        free(decoded);
        return SW_ERR_OVERFLOW;
    }

    memcpy(bits, decoded, out_bytes);
    *bit_len = decoded_bits;

    free(decoded);
    return SW_OK;
}

SW_API int sw_ofdm_modulate(const uint8_t* bits, size_t bit_len,
                            sw_config_t cfg, float* samples, size_t* sample_len) {
    if (!bits || !samples || !sample_len) return SW_ERR_BAD_PARAM;

    sw_signal sig = ofdm_modulate(bits, bit_len, cfg);
    if (!sig.data) return SW_ERR_MEMORY;

    if (sig.length > *sample_len) {
        *sample_len = sig.length;
        free(sig.data);
        return SW_ERR_OVERFLOW;
    }

    memcpy(samples, sig.data, sig.length * sizeof(float));
    *sample_len = sig.length;

    free(sig.data);
    return SW_OK;
}

SW_API int sw_ofdm_demodulate(const float* samples, size_t sample_len,
                              sw_config_t cfg, uint8_t* bits, size_t* bit_len) {
    if (!samples || !bits || !bit_len) return SW_ERR_BAD_PARAM;

    size_t out_bits_count = 0;
    uint8_t* decoded = NULL;
    int ret = ofdm_demodulate(samples, sample_len, cfg, &decoded, &out_bits_count);
    if (ret != SW_OK) {
        *bit_len = 0;
        return ret;
    }

    size_t decoded_bits = out_bits_count;
    if (decoded_bits > *bit_len) {
        *bit_len = decoded_bits;
        free(decoded);
        return SW_ERR_OVERFLOW;
    }

    size_t decoded_bytes = (decoded_bits + 7) / 8;
    memcpy(bits, decoded, decoded_bytes);
    *bit_len = decoded_bits;

    free(decoded);
    return SW_OK;
}

SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr) {
    if (!samples || !frame_start || !snr) return SW_ERR_BAD_PARAM;
    
    sync_config_t sync_cfg;
    memset(&sync_cfg, 0, sizeof(sync_cfg));
    sync_cfg.mode = cfg.modulation;
    sync_cfg.threshold = cfg.threshold;
    sync_cfg.zc_root = 1;
    
    int N = cfg.num_subcarriers;
    int N_guard = N / 8;
    int N_active = N / 2 - N_guard - 1;
    sync_cfg.zc_length = N_active;
    
    if (cfg.modulation == 0) {
        sync_cfg.matched_filter_len = (int)(cfg.symbol_duration * cfg.sample_rate + 0.5f);
        sync_cfg.carrier_freq = cfg.carrier_freq;
        sync_cfg.bandwidth = cfg.bandwidth;
        sync_cfg.sample_rate = (float)cfg.sample_rate;
    } else {
        sync_cfg.matched_filter_len = cfg.num_subcarriers + cfg.cp_length;
        sync_cfg.carrier_freq = cfg.carrier_freq;
        sync_cfg.bandwidth = cfg.bandwidth;
        sync_cfg.sample_rate = (float)cfg.sample_rate;
    }
    
    int ok = sync_detect_frame(samples, len, &sync_cfg, frame_start, snr);
    if (!ok) {
        return SW_ERR_SYNC;
    }
    return SW_OK;
}

SW_API int sw_estimate_cfo(const float* samples, size_t len,
                           sw_config_t cfg, float* cfo_hz) {
    if (!samples || !cfo_hz) return SW_ERR_BAD_PARAM;
    int N = cfg.num_subcarriers;
    int cp = cfg.cp_length;
    *cfo_hz = sync_schmidl_cox_cfo(samples, len, N + cp, (float)cfg.sample_rate);
    return SW_OK;
}

typedef struct {
    audio_capture_t* cap;
    ring_buffer_t* rb;
} sw_audio_capture_handle_t;

SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle) {
    if (!handle) return SW_ERR_BAD_PARAM;

    sw_audio_capture_handle_t* h = (sw_audio_capture_handle_t*)calloc(1, sizeof(sw_audio_capture_handle_t));
    if (!h) return SW_ERR_MEMORY;

    h->rb = ring_buffer_create((size_t)cfg.sample_rate);
    if (!h->rb) {
        free(h);
        return SW_ERR_MEMORY;
    }

    int ret = audio_capture_start(&h->cap, cfg.sample_rate, -1, h->rb);
    if (ret != SW_OK) {
        ring_buffer_destroy(h->rb);
        free(h);
        return ret;
    }

    *handle = h;
    return SW_OK;
}

SW_API int sw_audio_capture_stop(void* handle) {
    if (!handle) return SW_ERR_BAD_PARAM;
    sw_audio_capture_handle_t* h = (sw_audio_capture_handle_t*)handle;
    audio_capture_stop(h->cap);
    ring_buffer_destroy(h->rb);
    free(h);
    return SW_OK;
}

SW_API int sw_audio_capture_read(void* handle, float* buffer,
                                 size_t count, size_t* read) {
    if (!handle || !buffer || !read) return SW_ERR_BAD_PARAM;
    sw_audio_capture_handle_t* h = (sw_audio_capture_handle_t*)handle;
    return audio_capture_read(h->cap, buffer, count, read);
}

typedef struct {
    audio_playback_t* play;
    ring_buffer_t* rb;
} sw_audio_playback_handle_t;

SW_API int sw_audio_playback_start(sw_config_t cfg, void** handle) {
    if (!handle) return SW_ERR_BAD_PARAM;

    sw_audio_playback_handle_t* h = (sw_audio_playback_handle_t*)calloc(1, sizeof(sw_audio_playback_handle_t));
    if (!h) return SW_ERR_MEMORY;

    h->rb = ring_buffer_create((size_t)cfg.sample_rate);
    if (!h->rb) {
        free(h);
        return SW_ERR_MEMORY;
    }

    int ret = audio_playback_start(&h->play, cfg.sample_rate, -1, h->rb);
    if (ret != SW_OK) {
        ring_buffer_destroy(h->rb);
        free(h);
        return ret;
    }

    *handle = h;
    return SW_OK;
}

SW_API int sw_audio_playback_stop(void* handle) {
    if (!handle) return SW_ERR_BAD_PARAM;
    sw_audio_playback_handle_t* h = (sw_audio_playback_handle_t*)handle;
    audio_playback_stop(h->play);
    ring_buffer_destroy(h->rb);
    free(h);
    return SW_OK;
}

SW_API int sw_audio_playback_write(void* handle, const float* buffer,
                                   size_t count) {
    if (!handle || !buffer) return SW_ERR_BAD_PARAM;
    sw_audio_playback_handle_t* h = (sw_audio_playback_handle_t*)handle;
    return audio_playback_write(h->play, buffer, count);
}
