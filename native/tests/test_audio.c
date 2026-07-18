// Unit tests for audio I/O ring buffer.

#include "soundwave/audio.h"
#include <stdio.h>
#include <assert.h>

int main(void) {
    ring_buffer_t* rb = ring_buffer_create(4096);
    assert(rb != NULL);

    int16_t write_data[1000];
    for (int i = 0; i < 1000; i++) write_data[i] = (int16_t)i;
    ring_buffer_write(rb, write_data, 1000);
    printf("PASS: wrote 1000 samples\n");

    int16_t read_data[1000] = {0};
    ring_buffer_read(rb, read_data, 1000);
    assert(read_data[0] == 0 && read_data[999] == 999);
    printf("PASS: read back 1000 samples, verify OK\n");

    size_t avail = ring_buffer_available(rb);
    assert(avail == 0);
    printf("PASS: ring buffer empty as expected\n");

    ring_buffer_destroy(rb);
    printf("All audio tests passed.\n");
    return 0;
}
