// Audio I/O using miniaudio: capture, playback, ring buffer, device enumeration.

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "soundwave/audio.h"
#include "soundwave_api.h"
#include <stdlib.h>
#include <string.h>

// --- Ring Buffer ---

struct ring_buffer_t {
    int16_t* data;
    size_t   capacity;
    volatile size_t write_pos;
    volatile size_t read_pos;
};

ring_buffer_t* ring_buffer_create(size_t capacity_samples) {
    ring_buffer_t* rb = (ring_buffer_t*)calloc(1, sizeof(ring_buffer_t));
    if (!rb) return NULL;
    rb->data = (int16_t*)calloc(capacity_samples, sizeof(int16_t));
    if (!rb->data) {
        free(rb);
        return NULL;
    }
    rb->capacity = capacity_samples;
    rb->write_pos = 0;
    rb->read_pos = 0;
    return rb;
}

void ring_buffer_destroy(ring_buffer_t* rb) {
    if (rb) {
        free(rb->data);
        free(rb);
    }
}

int ring_buffer_write(ring_buffer_t* rb, const int16_t* data, size_t count) {
    if (!rb || !data) return -1;
    for (size_t i = 0; i < count; i++) {
        rb->data[rb->write_pos % rb->capacity] = data[i];
        rb->write_pos++;
    }
    return 0;
}

int ring_buffer_read(ring_buffer_t* rb, int16_t* data, size_t count) {
    if (!rb || !data) return -1;
    for (size_t i = 0; i < count; i++) {
        if (rb->read_pos < rb->write_pos) {
            data[i] = rb->data[rb->read_pos % rb->capacity];
        } else {
            data[i] = 0;
        }
        rb->read_pos++;
    }
    return 0;
}

size_t ring_buffer_available(ring_buffer_t* rb) {
    if (!rb) return 0;
    if (rb->write_pos >= rb->read_pos) {
        return rb->write_pos - rb->read_pos;
    }
    return 0;
}

void ring_buffer_clear(ring_buffer_t* rb) {
    if (rb) {
        rb->write_pos = 0;
        rb->read_pos = 0;
    }
}

// --- Audio Capture & Playback Structures ---

struct audio_capture_t {
    ma_device device;
    ring_buffer_t* rb;
    int running;
};

struct audio_playback_t {
    ma_device device;
    ring_buffer_t* rb;
    int running;
};

// --- Callback Implementations ---

static void capture_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pOutput;
    audio_capture_t* cap = (audio_capture_t*)pDevice->pUserData;
    if (cap && cap->rb && pInput) {
        ring_buffer_write(cap->rb, (const int16_t*)pInput, frameCount);
    }
}

static void playback_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput;
    audio_playback_t* play = (audio_playback_t*)pDevice->pUserData;
    if (play && play->rb && pOutput) {
        ring_buffer_read(play->rb, (int16_t*)pOutput, frameCount);
    }
}

// Helper to query device ID by index
static ma_result get_device_id_by_index(ma_device_type type, int index, ma_device_id* pID) {
    ma_context context;
    if (ma_context_init(NULL, 0, NULL, &context) != MA_SUCCESS) {
        return MA_ERROR;
    }

    ma_device_info* pPlaybackInfos;
    ma_uint32 playbackCount;
    ma_device_info* pCaptureInfos;
    ma_uint32 captureCount;
    if (ma_context_get_devices(&context, &pPlaybackInfos, &playbackCount, &pCaptureInfos, &captureCount) != MA_SUCCESS) {
        ma_context_uninit(&context);
        return MA_ERROR;
    }

    ma_result result = MA_ERROR;
    if (type == ma_device_type_playback && index < (int)playbackCount) {
        *pID = pPlaybackInfos[index].id;
        result = MA_SUCCESS;
    } else if (type == ma_device_type_capture && index < (int)captureCount) {
        *pID = pCaptureInfos[index].id;
        result = MA_SUCCESS;
    }

    ma_context_uninit(&context);
    return result;
}

// --- Public Control Functions ---

int audio_capture_start(audio_capture_t** cap, int sample_rate,
                        int device_id, ring_buffer_t* rb) {
    if (!cap || !rb) return SW_ERR_BAD_PARAM;

    audio_capture_t* c = (audio_capture_t*)calloc(1, sizeof(audio_capture_t));
    if (!c) return SW_ERR_MEMORY;

    c->rb = rb;
    c->running = 0;

    ma_device_config config = ma_device_config_init(ma_device_type_capture);
    config.capture.format = ma_format_s16;
    config.capture.channels = 1;
    config.sampleRate = sample_rate;
    config.pUserData = c;
    config.dataCallback = capture_callback;

    ma_device_id dev_id;
    if (device_id >= 0) {
        if (get_device_id_by_index(ma_device_type_capture, device_id, &dev_id) == MA_SUCCESS) {
            config.capture.pDeviceID = &dev_id;
        }
    }

    if (ma_device_init(NULL, &config, &c->device) != MA_SUCCESS) {
        free(c);
        return SW_ERR_AUDIO;
    }

    if (ma_device_start(&c->device) != MA_SUCCESS) {
        ma_device_uninit(&c->device);
        free(c);
        return SW_ERR_AUDIO;
    }

    c->running = 1;
    *cap = c;
    return SW_OK;
}

int audio_capture_stop(audio_capture_t* cap) {
    if (!cap) return SW_ERR_BAD_PARAM;
    ma_device_stop(&cap->device);
    ma_device_uninit(&cap->device);
    free(cap);
    return SW_OK;
}

int audio_capture_read(audio_capture_t* cap, float* samples,
                       size_t count, size_t* read) {
    if (!cap || !samples || !read) return SW_ERR_BAD_PARAM;
    size_t available = ring_buffer_available(cap->rb);
    size_t to_read = (count < available) ? count : available;

    if (to_read > 0) {
        int16_t* temp = (int16_t*)malloc(to_read * sizeof(int16_t));
        if (!temp) return SW_ERR_MEMORY;

        ring_buffer_read(cap->rb, temp, to_read);
        audio_int16_to_float(temp, to_read, samples);
        free(temp);
    }

    *read = to_read;
    return SW_OK;
}

int audio_playback_start(audio_playback_t** play, int sample_rate,
                         int device_id, ring_buffer_t* rb) {
    if (!play || !rb) return SW_ERR_BAD_PARAM;

    audio_playback_t* p = (audio_playback_t*)calloc(1, sizeof(audio_playback_t));
    if (!p) return SW_ERR_MEMORY;

    p->rb = rb;
    p->running = 0;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_s16;
    config.playback.channels = 1;
    config.sampleRate = sample_rate;
    config.pUserData = p;
    config.dataCallback = playback_callback;

    ma_device_id dev_id;
    if (device_id >= 0) {
        if (get_device_id_by_index(ma_device_type_playback, device_id, &dev_id) == MA_SUCCESS) {
            config.playback.pDeviceID = &dev_id;
        }
    }

    if (ma_device_init(NULL, &config, &p->device) != MA_SUCCESS) {
        free(p);
        return SW_ERR_AUDIO;
    }

    if (ma_device_start(&p->device) != MA_SUCCESS) {
        ma_device_uninit(&p->device);
        free(p);
        return SW_ERR_AUDIO;
    }

    p->running = 1;
    *play = p;
    return SW_OK;
}

int audio_playback_stop(audio_playback_t* play) {
    if (!play) return SW_ERR_BAD_PARAM;
    ma_device_stop(&play->device);
    ma_device_uninit(&play->device);
    free(play);
    return SW_OK;
}

int audio_playback_write(audio_playback_t* play, const float* samples,
                         size_t count) {
    if (!play || !samples) return SW_ERR_BAD_PARAM;
    if (count > 0) {
        int16_t* temp = (int16_t*)malloc(count * sizeof(int16_t));
        if (!temp) return SW_ERR_MEMORY;

        audio_float_to_int16(samples, count, temp);
        ring_buffer_write(play->rb, temp, count);
        free(temp);
    }
    return SW_OK;
}

int audio_enumerate_devices(int type, char*** names, int* count) {
    ma_context context;
    if (ma_context_init(NULL, 0, NULL, &context) != MA_SUCCESS) {
        *count = 0;
        return -1;
    }

    ma_device_info* pPlaybackInfos;
    ma_uint32 playbackCount;
    ma_device_info* pCaptureInfos;
    ma_uint32 captureCount;
    if (ma_context_get_devices(&context, &pPlaybackInfos, &playbackCount, &pCaptureInfos, &captureCount) != MA_SUCCESS) {
        ma_context_uninit(&context);
        *count = 0;
        return -1;
    }

    ma_uint32 dev_count = (type == 0) ? playbackCount : captureCount;
    ma_device_info* infos = (type == 0) ? pPlaybackInfos : pCaptureInfos;

    char** list = NULL;
    if (dev_count > 0) {
        list = (char**)malloc(dev_count * sizeof(char*));
        if (!list) {
            ma_context_uninit(&context);
            *count = 0;
            return -1;
        }
        for (ma_uint32 i = 0; i < dev_count; i++) {
            list[i] = strdup(infos[i].name);
        }
    }
    *names = list;
    *count = (int)dev_count;

    ma_context_uninit(&context);
    return 0;
}

void audio_free_device_list(char** names, int count) {
    if (names) {
        for (int i = 0; i < count; i++) {
            free(names[i]);
        }
        free(names);
    }
}

void audio_float_to_int16(const float* in, size_t count, int16_t* out) {
    if (!in || !out) return;
    for (size_t i = 0; i < count; i++) {
        float s = in[i] * 32767.0f;
        if (s > 32767.0f) s = 32767.0f;
        if (s < -32768.0f) s = -32768.0f;
        out[i] = (int16_t)s;
    }
}

void audio_int16_to_float(const int16_t* in, size_t count, float* out) {
    if (!in || !out) return;
    for (size_t i = 0; i < count; i++) {
        out[i] = (float)in[i] / 32768.0f;
    }
}
