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
#include <math.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Configuration validation (FFI trust boundary). See sw_config_validate() docs.
// ---------------------------------------------------------------------------

#define SW_MIN_SAMPLE_RATE   8000
#define SW_MAX_SAMPLE_RATE   192000
#define SW_DEFAULT_RATE      44100
#define SW_MIN_SF            6
#define SW_MAX_SF            12
#define SW_MIN_SUBCARRIERS   16
#define SW_MAX_SUBCARRIERS   4096
#define SW_MAX_SYMBOL_SEC    1.0f

static int is_pow2(int v) { return v > 0 && (v & (v - 1)) == 0; }

static int finite_nonneg(float v) { return isfinite(v) && v >= 0.0f; }

SW_API int sw_config_validate(sw_config_t cfg) {
    if (cfg.modulation != 0 && cfg.modulation != 1) return SW_ERR_BAD_PARAM;
    if (cfg.equalizer != 0 && cfg.equalizer != 1) return SW_ERR_BAD_PARAM;
    if (cfg.ofdm_modulation != 0 && cfg.ofdm_modulation != 1) return SW_ERR_BAD_PARAM;

    if (cfg.sample_rate != 0 &&
        (cfg.sample_rate < SW_MIN_SAMPLE_RATE || cfg.sample_rate > SW_MAX_SAMPLE_RATE))
        return SW_ERR_BAD_PARAM;
    float nyquist = 0.5f * (float)(cfg.sample_rate ? cfg.sample_rate : SW_DEFAULT_RATE);

    if (!isfinite(cfg.coding_rate)) return SW_ERR_BAD_PARAM;
    if (!finite_nonneg(cfg.threshold)) return SW_ERR_BAD_PARAM;
    if (!finite_nonneg(cfg.carrier_freq) || cfg.carrier_freq > nyquist) return SW_ERR_BAD_PARAM;
    if (!finite_nonneg(cfg.bandwidth) || cfg.bandwidth > nyquist) return SW_ERR_BAD_PARAM;
    if (!finite_nonneg(cfg.symbol_duration) || cfg.symbol_duration > SW_MAX_SYMBOL_SEC)
        return SW_ERR_BAD_PARAM;
    if (!finite_nonneg(cfg.amplitude) || cfg.amplitude > 1.0f) return SW_ERR_BAD_PARAM;

    if (cfg.sf != 0 && (cfg.sf < SW_MIN_SF || cfg.sf > SW_MAX_SF)) return SW_ERR_BAD_PARAM;

    int N = cfg.num_subcarriers;
    if (N != 0 && (!is_pow2(N) || N < SW_MIN_SUBCARRIERS || N > SW_MAX_SUBCARRIERS))
        return SW_ERR_BAD_PARAM;
    int n_eff = N ? N : 256; // OFDM default
    if (cfg.cp_length < 0 || cfg.cp_length > n_eff) return SW_ERR_BAD_PARAM;
    if (cfg.num_pilots < 0 || cfg.num_pilots > n_eff / 2) return SW_ERR_BAD_PARAM;
    return SW_OK;
}

SW_API const char* sw_version(void) { return SW_VERSION; }

SW_API int sw_crc32(const uint8_t* data, size_t len, uint32_t* crc) {
    if (!data || !crc) return SW_ERR_BAD_PARAM;
    if (len == 0) {
        *crc = 0;
        return SW_OK;
    }
    *crc = crc32_compute(data, len);
    return SW_OK;
}

SW_API int sw_rs_encode(const uint8_t* data, size_t data_len,
                        uint8_t* parity, size_t* parity_len) {
    if (!data || !parity || !parity_len || data_len == 0 || data_len > 223) return SW_ERR_BAD_PARAM;
    rs_encode(data, data_len, parity, data_len + 32);
    *parity_len = 32;
    return SW_OK;
}

SW_API int sw_rs_decode(uint8_t* data, size_t* data_len,
                        const uint8_t* parity, size_t parity_len,
                        int* errors_corrected) {
    if (!data || !data_len || !parity || !errors_corrected) return SW_ERR_BAD_PARAM;
    size_t k = *data_len;
    // Bound each term before adding so k + parity_len cannot wrap around.
    if (k == 0 || k > 255 || parity_len < 2 || parity_len > 255 - k) return SW_ERR_BAD_PARAM;
    size_t n = k + parity_len;

    uint8_t r[255];
    memcpy(r, data, k);
    memcpy(r + k, parity, parity_len);

    // The parity length is known here: never let the decoder guess it from n.
    int errs = rs_decode_nsym(r, n, parity_len);
    if (errs < 0) {
        return SW_ERR_DECODE;
    }

    memcpy(data, r, k);
    *errors_corrected = errs;
    return SW_OK;
}

SW_API int sw_css_modulate(const uint8_t* bits, size_t bit_len,
                           sw_config_t cfg, float* samples, size_t* sample_len) {
    if (!bits || !samples || !sample_len || bit_len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;

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
    if (!samples || !bits || !bit_len || sample_len == 0 || *bit_len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;

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
    if (!bits || !samples || !sample_len || bit_len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;

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
    if (!samples || !bits || !bit_len || sample_len == 0 || *bit_len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;

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

SW_API int sw_ofdm_equalized_symbols(const float* samples, size_t sample_len,
                                     sw_config_t cfg, float* iq, size_t* num_points) {
    if (!samples || !iq || !num_points || sample_len == 0 || *num_points == 0)
        return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK || cfg.modulation != 1) return SW_ERR_BAD_PARAM;

    // Every OFDM symbol spans more samples than it has data subcarriers, so a
    // frame can never yield more points than input samples. Bounding the
    // scratch buffer by sample_len keeps a huge advertised capacity from
    // driving the allocation size.
    size_t cap = *num_points < sample_len ? *num_points : sample_len;
    *num_points = 0;
    if (cap > SIZE_MAX / sizeof(kiss_fft_cpx)) return SW_ERR_MEMORY;
    kiss_fft_cpx* points = (kiss_fft_cpx*)malloc(cap * sizeof(kiss_fft_cpx));
    if (!points) return SW_ERR_MEMORY;

    uint8_t* decoded = NULL;
    size_t decoded_bits = 0;
    size_t count = 0;
    int ret = ofdm_demodulate_ex(samples, sample_len, cfg, &decoded, &decoded_bits,
                                 points, cap, &count);
    free(decoded);
    if (ret != SW_OK) {
        free(points);
        return ret;
    }
    for (size_t i = 0; i < count; i++) {
        iq[2 * i] = (float)points[i].r;
        iq[2 * i + 1] = (float)points[i].i;
    }
    *num_points = count;
    free(points);
    return SW_OK;
}

SW_API int sw_detect_frame(const float* samples, size_t len,
                           sw_config_t cfg, size_t* frame_start, float* snr) {
    if (!samples || !frame_start || !snr || len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;
    
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
    if (!samples || !cfo_hz || len == 0) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;
    // Same defaults as the OFDM modules (config already validated).
    int N = cfg.num_subcarriers ? cfg.num_subcarriers : 256;
    int cp = cfg.cp_length ? cfg.cp_length : N / 8;
    int fs = cfg.sample_rate ? cfg.sample_rate : SW_DEFAULT_RATE;
    size_t period = (size_t)N + (size_t)cp;
    if (len < 2 * period) return SW_ERR_SYNC; // two repeated symbols required
    *cfo_hz = sync_schmidl_cox_cfo(samples, len, (int)period, (float)fs);
    return SW_OK;
}

typedef struct {
    audio_capture_t* cap;
    ring_buffer_t* rb;
} sw_audio_capture_handle_t;

SW_API int sw_audio_capture_start(sw_config_t cfg, void** handle) {
    if (!handle) return SW_ERR_BAD_PARAM;
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;
    if (cfg.sample_rate == 0) cfg.sample_rate = SW_DEFAULT_RATE;

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
    if (sw_config_validate(cfg) != SW_OK) return SW_ERR_BAD_PARAM;
    if (cfg.sample_rate == 0) cfg.sample_rate = SW_DEFAULT_RATE;

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

/* ------------------------------------------------------------------------
 * AGC (issue #92). Handles carry a magic tag so a stale or garbage pointer
 * passed across the FFI boundary is rejected instead of dereferenced as an
 * AGC state; the tag is cleared on destroy.
 * ------------------------------------------------------------------------ */

#include "soundwave/agc.h"
#include <math.h>

#define SW_AGC_MAGIC 0x41474331u /* "AGC1" */

typedef struct {
    uint32_t magic;
    agc_state_t* agc;
} sw_agc_handle_t;

static sw_agc_handle_t* agc_handle(void* handle) {
    sw_agc_handle_t* h = (sw_agc_handle_t*)handle;
    return (h && h->magic == SW_AGC_MAGIC && h->agc) ? h : NULL;
}

SW_API int sw_agc_create(int sample_rate, float target_rms, void** handle) {
    if (!handle) return SW_ERR_BAD_PARAM;
    *handle = NULL;
    if (target_rms == 0.0f) target_rms = AGC_DEFAULT_TARGET_RMS;
    if (sample_rate < 8000 || sample_rate > 192000 || !isfinite(target_rms) ||
        target_rms <= 0.0f || target_rms > 1.0f)
        return SW_ERR_BAD_PARAM;
    sw_agc_handle_t* h = (sw_agc_handle_t*)calloc(1, sizeof(*h));
    if (!h) return SW_ERR_MEMORY;
    h->agc = agc_create((float)sample_rate, target_rms);
    if (!h->agc) {
        free(h);
        return SW_ERR_MEMORY;
    }
    h->magic = SW_AGC_MAGIC;
    *handle = h;
    return SW_OK;
}

SW_API int sw_agc_process(void* handle, float* samples, size_t len) {
    sw_agc_handle_t* h = agc_handle(handle);
    if (!h || (!samples && len > 0)) return SW_ERR_BAD_PARAM;
    return agc_process(h->agc, samples, len) == 0 ? SW_OK : SW_ERR_BAD_PARAM;
}

SW_API int sw_agc_get_gain_db(void* handle, float* gain_db) {
    sw_agc_handle_t* h = agc_handle(handle);
    if (!h || !gain_db) return SW_ERR_BAD_PARAM;
    *gain_db = agc_gain_db(h->agc);
    return SW_OK;
}

SW_API int sw_agc_reset(void* handle) {
    sw_agc_handle_t* h = agc_handle(handle);
    if (!h) return SW_ERR_BAD_PARAM;
    agc_reset(h->agc);
    return SW_OK;
}

SW_API int sw_agc_destroy(void* handle) {
    sw_agc_handle_t* h = agc_handle(handle);
    if (!h) return SW_ERR_BAD_PARAM;
    agc_destroy(h->agc);
    h->agc = NULL;
    h->magic = 0;
    free(h);
    return SW_OK;
}
