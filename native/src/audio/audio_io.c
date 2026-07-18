// Audio I/O using miniaudio: capture, playback, ring buffer, device enumeration.

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
    rb->data = (int16_t*)calloc(capacity_samples, sizeof(int16_t));
    rb->capacity = capacity_samples;
    rb->write_pos = 0;
    rb->read_pos = 0;
    return rb;
}

void ring_buffer_destroy(ring_buffer_t* rb) {
    if (rb) { free(rb->data); free(rb); }
}

int ring_buffer_write(ring_buffer_t* rb, const int16_t* data, size_t count) {
    for (size_t i = 0; i < count; i++) {
        rb->data[rb->write_pos % rb->capacity] = data[i];
        rb->write_pos++;
    }
    return 0;
}

int ring_buffer_read(ring_buffer_t* rb, int16_t* data, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (rb->read_pos < rb->write_pos)
            data[i] = rb->data[rb->read_pos % rb->capacity];
        else
            data[i] = 0;
        rb->read_pos++;
    }
    return 0;
}

size_t ring_buffer_available(ring_buffer_t* rb) {
    return rb->write_pos - rb->read_pos;
}

void ring_buffer_clear(ring_buffer_t* rb) {
    rb->write_pos = 0;
    rb->read_pos = 0;
}

// --- Audio Capture / Playback stubs ---

int audio_capture_start(audio_capture_t** cap, int sample_rate,
                        int device_id, ring_buffer_t* rb) {
    (void)cap; (void)sample_rate; (void)device_id; (void)rb;
    return SW_ERR_NOT_IMPLEMENTED;
}

int audio_capture_stop(audio_capture_t* cap) { (void)cap; return SW_ERR_NOT_IMPLEMENTED; }

int audio_capture_read(audio_capture_t* cap, float* samples,
                       size_t count, size_t* read) {
    (void)cap; (void)samples; (void)count; (void)read;
    return SW_ERR_NOT_IMPLEMENTED;
}

int audio_playback_start(audio_playback_t** play, int sample_rate,
                         int device_id, ring_buffer_t* rb) {
    (void)play; (void)sample_rate; (void)device_id; (void)rb;
    return SW_ERR_NOT_IMPLEMENTED;
}

int audio_playback_stop(audio_playback_t* play) { (void)play; return SW_ERR_NOT_IMPLEMENTED; }

int audio_playback_write(audio_playback_t* play, const float* samples,
                         size_t count) {
    (void)play; (void)samples; (void)count;
    return SW_ERR_NOT_IMPLEMENTED;
}

int audio_enumerate_devices(int type, char*** names, int* count) {
    (void)type; (void)names;
    *count = 0;
    return 0;
}

void audio_free_device_list(char** names, int count) {
    for (int i = 0; i < count; i++) free(names[i]);
    free(names);
}

void audio_float_to_int16(const float* in, size_t count, int16_t* out) {
    for (size_t i = 0; i < count; i++) {
        float s = in[i] * 32767.0f;
        if (s > 32767.0f) s = 32767.0f;
        if (s < -32768.0f) s = -32768.0f;
        out[i] = (int16_t)s;
    }
}

void audio_int16_to_float(const int16_t* in, size_t count, float* out) {
    for (size_t i = 0; i < count; i++)
        out[i] = (float)in[i] / 32768.0f;
}
