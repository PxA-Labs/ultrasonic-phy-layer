// Audio I/O layer wrapping miniaudio. Provides capture (mic), playback (speaker),
// device enumeration, and a thread-safe ring buffer for sample transfer.

#ifndef SOUNDWAVE_AUDIO_H
#define SOUNDWAVE_AUDIO_H

#include <stddef.h>
#include <stdint.h>

// Thread-safe ring buffer for sample transfer between audio callback and app.
typedef struct ring_buffer_t ring_buffer_t;

ring_buffer_t* ring_buffer_create(size_t capacity_samples);
void           ring_buffer_destroy(ring_buffer_t* rb);
int            ring_buffer_write(ring_buffer_t* rb, const int16_t* data, size_t count);
int            ring_buffer_read(ring_buffer_t* rb, int16_t* data, size_t count);
size_t         ring_buffer_available(ring_buffer_t* rb);
void           ring_buffer_clear(ring_buffer_t* rb);

// Audio capture (microphone -> ring buffer).
typedef struct audio_capture_t audio_capture_t;
int  audio_capture_start(audio_capture_t** cap, int sample_rate,
                         int device_id, ring_buffer_t* rb);
int  audio_capture_stop(audio_capture_t* cap);
int  audio_capture_read(audio_capture_t* cap, float* samples,
                        size_t count, size_t* read);

// Audio playback (ring buffer -> speaker).
typedef struct audio_playback_t audio_playback_t;
int  audio_playback_start(audio_playback_t** play, int sample_rate,
                          int device_id, ring_buffer_t* rb);
int  audio_playback_stop(audio_playback_t* play);
int  audio_playback_write(audio_playback_t* play, const float* samples,
                          size_t count);

// Device enumeration.
int  audio_enumerate_devices(int type, char*** names, int* count);
void audio_free_device_list(char** names, int count);

// Sample format conversion.
void audio_float_to_int16(const float* in, size_t count, int16_t* out);
void audio_int16_to_float(const int16_t* in, size_t count, float* out);

#endif // SOUNDWAVE_AUDIO_H
