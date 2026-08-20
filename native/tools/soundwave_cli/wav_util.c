#include "wav_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 1)
typedef struct {
    char     riff_id[4];      // "RIFF"
    uint32_t riff_sz;        // File size - 8
    char     wave_id[4];      // "WAVE"
    char     fmt_id[4];       // "fmt "
    uint32_t fmt_sz;        // Chunk size (usually 16)
    uint16_t audio_format;    // 1 = PCM, 3 = IEEE float
    uint16_t num_channels;    // 1 = mono, 2 = stereo
    uint32_t sample_rate;     // Sampling rate (44100)
    uint32_t byte_rate;       // sample_rate * num_channels * (bits_per_sample/8)
    uint16_t block_align;     // num_channels * (bits_per_sample/8)
    uint16_t bits_per_sample; // 16 or 32
    char     data_id[4];      // "data"
    uint32_t data_sz;        // Chunk size in bytes
} wav_header_t;
#pragma pack(pop)

int wav_write_mono_i16(const char* filename, const float* samples, size_t num_samples, uint32_t sample_rate) {
    FILE* f = fopen(filename, "wb");
    if (!f) {
        return -1;
    }

    uint32_t data_sz = (uint32_t)(num_samples * sizeof(int16_t));
    wav_header_t header;
    
    memcpy(header.riff_id, "RIFF", 4);
    header.riff_sz = 36 + data_sz;
    memcpy(header.wave_id, "WAVE", 4);
    memcpy(header.fmt_id, "fmt ", 4);
    header.fmt_sz = 16;
    header.audio_format = 1; // PCM
    header.num_channels = 1; // Mono
    header.sample_rate = sample_rate;
    header.bits_per_sample = 16;
    header.block_align = 2; // 1 channel * 2 bytes/sample
    header.byte_rate = sample_rate * 2;
    memcpy(header.data_id, "data", 4);
    header.data_sz = data_sz;

    if (fwrite(&header, sizeof(wav_header_t), 1, f) != 1) {
        fclose(f);
        return -1;
    }

    int16_t* pcm = (int16_t*)malloc(num_samples * sizeof(int16_t));
    if (!pcm) {
        fclose(f);
        return -1;
    }

    for (size_t i = 0; i < num_samples; i++) {
        float s = samples[i];
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        pcm[i] = (int16_t)(s * 32767.0f);
    }

    size_t written = fwrite(pcm, sizeof(int16_t), num_samples, f);
    free(pcm);
    fclose(f);

    return (written == num_samples) ? 0 : -1;
}

int wav_read_mono(const char* filename, float** out_samples, size_t* out_num_samples, uint32_t* out_sample_rate) {
    FILE* f = fopen(filename, "rb");
    if (!f) {
        return -1;
    }

    // Read RIFF and WAVE headers
    char riff_id[4];
    uint32_t riff_sz;
    char wave_id[4];

    if (fread(riff_id, 1, 4, f) != 4 || memcmp(riff_id, "RIFF", 4) != 0 ||
        fread(&riff_sz, 4, 1, f) != 1 ||
        fread(wave_id, 1, 4, f) != 4 || memcmp(wave_id, "WAVE", 4) != 0) {
        fclose(f);
        return -1;
    }

    // Read format chunk
    char chunk_id[4];
    uint32_t chunk_sz;
    uint16_t audio_format = 0;
    uint16_t num_channels = 0;
    uint32_t sample_rate = 0;
    uint16_t bits_per_sample = 0;

    int found_fmt = 0;
    int found_data = 0;
    uint32_t data_sz = 0;

    while (fread(chunk_id, 1, 4, f) == 4 && fread(&chunk_sz, 4, 1, f) == 1) {
        if (memcmp(chunk_id, "fmt ", 4) == 0) {
            found_fmt = 1;
            if (fread(&audio_format, 2, 1, f) != 1 ||
                fread(&num_channels, 2, 1, f) != 1 ||
                fread(&sample_rate, 4, 1, f) != 1 ||
                fseek(f, 6, SEEK_CUR) != 0 || // skip byte_rate and block_align
                fread(&bits_per_sample, 2, 1, f) != 1) {
                fclose(f);
                return -1;
            }
            // Skip any extra format chunk bytes
            if (chunk_sz > 16) {
                if (fseek(f, chunk_sz - 16, SEEK_CUR) != 0) {
                    fclose(f);
                    return -1;
                }
            }
        } else if (memcmp(chunk_id, "data", 4) == 0) {
            found_data = 1;
            data_sz = chunk_sz;
            break; // Data chunk found, stop scanning
        } else {
            // Skip unknown chunk
            if (fseek(f, chunk_sz, SEEK_CUR) != 0) {
                fclose(f);
                return -1;
            }
        }
    }

    if (!found_fmt || !found_data) {
        fclose(f);
        return -1;
    }

    if (audio_format != 1 && audio_format != 3) {
        // Only PCM (1) and IEEE Float (3) are supported
        fclose(f);
        return -1;
    }

    if (num_channels != 1 && num_channels != 2) {
        // Only mono and stereo are supported
        fclose(f);
        return -1;
    }

    size_t bytes_per_sample = bits_per_sample / 8;
    if (bytes_per_sample == 0) {
        fclose(f);
        return -1;
    }

    size_t total_samples = data_sz / (num_channels * bytes_per_sample);
    if (total_samples == 0) {
        fclose(f);
        return -1;
    }

    float* samples = (float*)malloc(total_samples * sizeof(float));
    if (!samples) {
        fclose(f);
        return -1;
    }

    for (size_t i = 0; i < total_samples; i++) {
        float val = 0.0f;
        if (num_channels == 1) {
            if (audio_format == 1) { // PCM
                if (bits_per_sample == 16) {
                    int16_t s;
                    if (fread(&s, 2, 1, f) != 1) break;
                    val = (float)s / 32768.0f;
                } else if (bits_per_sample == 8) {
                    uint8_t s;
                    if (fread(&s, 1, 1, f) != 1) break;
                    val = ((float)s - 128.0f) / 128.0f;
                } else {
                    free(samples);
                    fclose(f);
                    return -1;
                }
            } else if (audio_format == 3) { // Float
                if (bits_per_sample == 32) {
                    float s;
                    if (fread(&s, 4, 1, f) != 1) break;
                    val = s;
                } else {
                    free(samples);
                    fclose(f);
                    return -1;
                }
            }
        } else { // Stereo (2 channels) - read both, average them
            if (audio_format == 1) { // PCM
                if (bits_per_sample == 16) {
                    int16_t s[2];
                    if (fread(s, 2, 2, f) != 2) break;
                    val = ((float)s[0] + (float)s[1]) / 65536.0f;
                } else if (bits_per_sample == 8) {
                    uint8_t s[2];
                    if (fread(s, 1, 2, f) != 2) break;
                    val = (((float)s[0] - 128.0f) + ((float)s[1] - 128.0f)) / 256.0f;
                } else {
                    free(samples);
                    fclose(f);
                    return -1;
                }
            } else if (audio_format == 3) { // Float
                if (bits_per_sample == 32) {
                    float s[2];
                    if (fread(s, 4, 2, f) != 2) break;
                    val = (s[0] + s[1]) / 2.0f;
                } else {
                    free(samples);
                    fclose(f);
                    return -1;
                }
            }
        }
        samples[i] = val;
    }

    fclose(f);

    *out_samples = samples;
    *out_num_samples = total_samples;
    *out_sample_rate = sample_rate;

    return 0;
}
