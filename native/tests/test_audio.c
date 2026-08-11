// Comprehensive unit tests for audio I/O, ring buffer, format conversions, and device enumeration.

#include "soundwave/audio.h"
#include "soundwave_api.h"
#include "miniaudio.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#define sleep_ms(ms) Sleep(ms)
#else
#include <unistd.h>
#define sleep_ms(ms) usleep((ms) * 1000)
#endif

void test_ring_buffer(void) {
    printf("Running ring buffer tests...\n");

    // 1. Basic create/destroy
    ring_buffer_t* rb = ring_buffer_create(4096);
    assert(rb != NULL);

    // 2. Write and Read back 1000 samples
    int16_t write_data[1000];
    for (int i = 0; i < 1000; i++) write_data[i] = (int16_t)i;
    int ret = ring_buffer_write(rb, write_data, 1000);
    assert(ret == 0);
    assert(ring_buffer_available(rb) == 1000);

    int16_t read_data[1000] = {0};
    ret = ring_buffer_read(rb, read_data, 1000);
    assert(ret == 0);
    for (int i = 0; i < 1000; i++) {
        assert(read_data[i] == (int16_t)i);
    }
    assert(ring_buffer_available(rb) == 0);

    // 3. Ring buffer write 2000, read 1000 -> available 1000
    int16_t write_data_large[2000];
    for (int i = 0; i < 2000; i++) write_data_large[i] = (int16_t)(i * 2);
    ring_buffer_write(rb, write_data_large, 2000);
    assert(ring_buffer_available(rb) == 2000);

    int16_t read_data_half[1000] = {0};
    ring_buffer_read(rb, read_data_half, 1000);
    for (int i = 0; i < 1000; i++) {
        assert(read_data_half[i] == (int16_t)(i * 2));
    }
    assert(ring_buffer_available(rb) == 1000);

    // Read remaining 1000
    ring_buffer_read(rb, read_data_half, 1000);
    for (int i = 0; i < 1000; i++) {
        assert(read_data_half[i] == (int16_t)((i + 1000) * 2));
    }
    assert(ring_buffer_available(rb) == 0);

    // 4. Test ring buffer clear
    ring_buffer_write(rb, write_data, 500);
    assert(ring_buffer_available(rb) == 500);
    ring_buffer_clear(rb);
    assert(ring_buffer_available(rb) == 0);

    // 5. Test underflow (reading more than available returns 0s)
    int16_t underflow_buf[10];
    ring_buffer_read(rb, underflow_buf, 10);
    for (int i = 0; i < 10; i++) {
        assert(underflow_buf[i] == 0);
    }

    ring_buffer_destroy(rb);
    printf("PASS: ring buffer tests completed.\n");
}

void test_conversions(void) {
    printf("Running audio conversion tests...\n");

    // Float to Int16 and back
    float float_in[5] = { 0.0f, 0.5f, 1.0f, -0.5f, -1.0f };
    int16_t int_out[5];

    audio_float_to_int16(float_in, 5, int_out);
    assert(int_out[0] == 0);
    assert(int_out[1] == 16383);
    assert(int_out[2] == 32767);
    assert(int_out[3] == -16383 || int_out[3] == -16384);
    assert(int_out[4] == -32767);

    // Check clipping
    float float_clip[2] = { 1.5f, -2.0f };
    int16_t int_clip[2];
    audio_float_to_int16(float_clip, 2, int_clip);
    assert(int_clip[0] == 32767);
    assert(int_clip[1] == -32768);

    // Int16 to Float
    int16_t int_in[5] = { 0, 16384, 32767, -16384, -32768 };
    float float_out[5];
    audio_int16_to_float(int_in, 5, float_out);

    assert(fabsf(float_out[0] - 0.0f) < 1e-4f);
    assert(fabsf(float_out[1] - 0.5f) < 1e-4f);
    assert(fabsf(float_out[2] - 0.9999f) < 1e-3f);
    assert(fabsf(float_out[3] - (-0.5f)) < 1e-4f);
    assert(fabsf(float_out[4] - (-1.0f)) < 1e-4f);

    printf("PASS: audio conversions tests completed.\n");
}

void test_devices(void) {
    printf("Running device enumeration tests...\n");

    char** playback_names = NULL;
    int playback_count = 0;
    int ret = audio_enumerate_devices(0, &playback_names, &playback_count);
    assert(ret == 0);
    printf("Found %d playback devices:\n", playback_count);
    for (int i = 0; i < playback_count; i++) {
        printf("  - %s\n", playback_names[i]);
    }
    audio_free_device_list(playback_names, playback_count);

    char** capture_names = NULL;
    int capture_count = 0;
    ret = audio_enumerate_devices(1, &capture_names, &capture_count);
    assert(ret == 0);
    printf("Found %d capture devices:\n", capture_count);
    for (int i = 0; i < capture_count; i++) {
        printf("  - %s\n", capture_names[i]);
    }
    audio_free_device_list(capture_names, capture_count);

    printf("PASS: device enumeration tests completed.\n");
}

void test_live_audio(void) {
    printf("Running live audio capture & playback tests...\n");

    sw_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.sample_rate = 44100;

    void* capture_handle = NULL;
    int ret = sw_audio_capture_start(cfg, &capture_handle);
    if (ret != SW_OK) {
        printf("WARNING: Capture start failed or no audio device available (error code %d). Skipping live tests.\n", ret);
        return;
    }
    assert(capture_handle != NULL);
    printf("Capture started successfully.\n");

    // Sleep for 100 milliseconds to let it capture some samples
    sleep_ms(100);

    float read_samples[4410];
    size_t samples_read = 0;
    ret = sw_audio_capture_read(capture_handle, read_samples, 4410, &samples_read);
    assert(ret == SW_OK);
    printf("Captured %zu samples of audio in 100ms.\n", samples_read);

    ret = sw_audio_capture_stop(capture_handle);
    assert(ret == SW_OK);
    printf("Capture stopped successfully.\n");

    // Playback check
    void* playback_handle = NULL;
    ret = sw_audio_playback_start(cfg, &playback_handle);
    if (ret != SW_OK) {
        printf("WARNING: Playback start failed or no device (error code %d).\n", ret);
        return;
    }
    assert(playback_handle != NULL);

    float tone[4410];
    for (int i = 0; i < 4410; i++) {
        tone[i] = 0.5f * sinf(2.0f * 3.14159f * 440.0f * (float)i / 44100.0f);
    }
    ret = sw_audio_playback_write(playback_handle, tone, 4410);
    assert(ret == SW_OK);
    printf("Wrote 100ms tone to playback buffer.\n");

    sleep_ms(50);
    ret = sw_audio_playback_stop(playback_handle);
    assert(ret == SW_OK);
    printf("Playback stopped successfully.\n");

    printf("PASS: live audio capture & playback tests completed.\n");
}

int main(void) {
    test_ring_buffer();
    test_conversions();
    test_devices();
    test_live_audio();
    printf("All audio/API tests passed.\n");
    return 0;
}
