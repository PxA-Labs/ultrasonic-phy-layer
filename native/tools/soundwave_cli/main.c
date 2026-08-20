#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include "soundwave_api.h"
#include "wav_util.h"

// Box-Muller transform to generate zero-mean Gaussian distributed random noise with variance std_dev^2
static float generate_gaussian_noise(float std_dev) {
    float u1 = (float)rand() / (float)RAND_MAX;
    float u2 = (float)rand() / (float)RAND_MAX;
    if (u1 < 1e-10f) u1 = 1e-10f; // avoid log(0)
    float z0 = sqrtf(-2.0f * logf(u1)) * cosf(6.283185307179586f * u2);
    return z0 * std_dev;
}

// Injects AWGN to a signal to match a target SNR (in dB)
static void add_awgn_noise(const float* signal, size_t len, float snr_db, float* noisy_signal) {
    double sum_sq = 0.0;
    for (size_t i = 0; i < len; i++) {
        sum_sq += (double)signal[i] * (double)signal[i];
    }
    float signal_power = (float)(sum_sq / (double)len);
    if (signal_power < 1e-10f) signal_power = 1e-10f;
    float noise_power = signal_power / powf(10.0f, snr_db / 10.0f);
    float std_dev = sqrtf(noise_power);

    for (size_t i = 0; i < len; i++) {
        noisy_signal[i] = signal[i] + generate_gaussian_noise(std_dev);
    }
}

static void print_usage(void) {
    fprintf(stderr, "Soundwave standalone CLI tool - v%s\n", sw_version());
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  soundwave-cli modulate --mode <css|ofdm> --input <text> --output <filename.wav> [options]\n");
    fprintf(stderr, "  soundwave-cli demodulate --mode <css|ofdm> --input <filename.wav> [options]\n");
    fprintf(stderr, "  soundwave-cli simulate --input <filename.wav> --snr <snr_db> --output <filename.wav>\n\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --sf <sf>                  Spreading factor for CSS modulation (7..12; default 8)\n");
    fprintf(stderr, "  --fft <size>               FFT size for OFDM (256, 512, 1024, 2048; default 256)\n");
    fprintf(stderr, "  --cp <length>              Cyclic prefix length for OFDM (default 64)\n");
    fprintf(stderr, "  --freq <freq_hz>           Carrier frequency in Hz (default 19000.0)\n");
    fprintf(stderr, "  --bw <bw_hz>               Bandwidth in Hz (default 2000.0)\n");
    fprintf(stderr, "  --amp <amp>                Amplitude scaling (0.0 to 1.0; default 0.8)\n");
    fprintf(stderr, "  --equalizer <zf|mmse>      Equalizer for OFDM demodulation (default zf)\n");
}

int main(int argc, char** argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);

    if (argc < 2) {
        print_usage();
        return 1;
    }

    const char* command = argv[1];

    if (strcmp(command, "modulate") == 0) {
        const char* mode = NULL;
        const char* input = NULL;
        const char* output = NULL;

        // Configuration defaults
        sw_config_t cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.sample_rate = 44100;
        cfg.modulation = 0; // CSS
        cfg.sf = 8;
        cfg.num_subcarriers = 256;
        cfg.cp_length = 64;
        cfg.num_pilots = 8;
        cfg.coding_rate = 0.5f;
        cfg.threshold = 3.0f;
        cfg.equalizer = 0; // ZF
        cfg.carrier_freq = 19000.0f;
        cfg.bandwidth = 2000.0f;
        cfg.symbol_duration = 0.02f;
        cfg.amplitude = 0.8f;
        cfg.ofdm_modulation = 1; // QPSK

        // Parse command options
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
                mode = argv[++i];
            } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
                input = argv[++i];
            } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
                output = argv[++i];
            } else if (strcmp(argv[i], "--sf") == 0 && i + 1 < argc) {
                cfg.sf = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--fft") == 0 && i + 1 < argc) {
                cfg.num_subcarriers = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--cp") == 0 && i + 1 < argc) {
                cfg.cp_length = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--freq") == 0 && i + 1 < argc) {
                cfg.carrier_freq = (float)atof(argv[++i]);
            } else if (strcmp(argv[i], "--bw") == 0 && i + 1 < argc) {
                cfg.bandwidth = (float)atof(argv[++i]);
            } else if (strcmp(argv[i], "--amp") == 0 && i + 1 < argc) {
                cfg.amplitude = (float)atof(argv[++i]);
            }
        }

        if (!mode || !input || !output) {
            fprintf(stderr, "Error: Missing required arguments (--mode, --input, --output).\n\n");
            print_usage();
            return 1;
        }

        if (strcmp(mode, "css") == 0) {
            cfg.modulation = 0;
        } else if (strcmp(mode, "ofdm") == 0) {
            cfg.modulation = 1;
        } else {
            fprintf(stderr, "Error: Invalid mode '%s'. Choose 'css' or 'ofdm'.\n", mode);
            return 1;
        }

        size_t input_len = strlen(input);
        if (input_len == 0) {
            fprintf(stderr, "Error: Input text is empty.\n");
            return 1;
        }
        if (input_len > 223 - 6) {
            fprintf(stderr, "Error: Input text is too long (max %d bytes).\n", 223 - 6);
            return 1;
        }

        // Calculate CRC-32
        uint32_t crc;
        int ret = sw_crc32((const uint8_t*)input, input_len, &crc);
        if (ret != SW_OK) {
            fprintf(stderr, "Error: CRC-32 calculation failed: %d\n", ret);
            return 1;
        }

        // Build packet: [CRC (4 bytes)][Length (2 bytes)][Payload]
        size_t packet_len = 6 + input_len;
        uint8_t* packet = (uint8_t*)malloc(packet_len);
        if (!packet) {
            fprintf(stderr, "Error: Out of memory.\n");
            return 1;
        }
        packet[0] = (uint8_t)(crc & 0xFF);
        packet[1] = (uint8_t)((crc >> 8) & 0xFF);
        packet[2] = (uint8_t)((crc >> 16) & 0xFF);
        packet[3] = (uint8_t)((crc >> 24) & 0xFF);
        packet[4] = (uint8_t)(input_len & 0xFF);
        packet[5] = (uint8_t)((input_len >> 8) & 0xFF);
        memcpy(packet + 6, input, input_len);

        // Apply Reed-Solomon encoding (outputs exactly 32 bytes of parity)
        uint8_t parity[32];
        size_t parity_len = 32;
        ret = sw_rs_encode(packet, packet_len, parity, &parity_len);
        if (ret != SW_OK) {
            fprintf(stderr, "Error: Reed-Solomon encoding failed: %d\n", ret);
            free(packet);
            return 1;
        }

        // Build final frame: [packet][parity]
        size_t frame_len = packet_len + 32;
        uint8_t* frame = (uint8_t*)malloc(frame_len);
        if (!frame) {
            fprintf(stderr, "Error: Out of memory.\n");
            free(packet);
            return 1;
        }
        memcpy(frame, packet, packet_len);
        memcpy(frame + packet_len, parity, 32);
        free(packet);

        // Modulate signal
        size_t max_samples = 4000000;
        float* samples = (float*)malloc(max_samples * sizeof(float));
        if (!samples) {
            fprintf(stderr, "Error: Out of memory.\n");
            free(frame);
            return 1;
        }
        size_t sample_len = max_samples;

        if (cfg.modulation == 0) {
            ret = sw_css_modulate(frame, frame_len * 8, cfg, samples, &sample_len);
        } else {
            ret = sw_ofdm_modulate(frame, frame_len * 8, cfg, samples, &sample_len);
        }

        free(frame);

        if (ret != SW_OK) {
            fprintf(stderr, "Error: Modulation failed with code %d\n", ret);
            free(samples);
            return 1;
        }

        // Check peak amplitude and scale if necessary to avoid WAV clipping
        float peak = 0.0f;
        for (size_t i = 0; i < sample_len; i++) {
            float abs_val = fabsf(samples[i]);
            if (abs_val > peak) peak = abs_val;
        }
        fprintf(stderr, "DEBUG: Modulated signal peak amplitude = %.4f\n", peak);
        if (peak > 1.0f) {
            float scale = 0.8f / peak;
            for (size_t i = 0; i < sample_len; i++) {
                samples[i] *= scale;
            }
            fprintf(stderr, "DEBUG: Scaled signal by %.4f to avoid WAV clipping\n", scale);
        }

        // Pad the signal with 64 zero samples at the end to prevent timing truncation
        if (sample_len + 64 < max_samples) {
            memset(samples + sample_len, 0, 64 * sizeof(float));
            sample_len += 64;
        }

        // Export to WAV
        if (wav_write_mono_i16(output, samples, sample_len, cfg.sample_rate) != 0) {
            fprintf(stderr, "Error: Failed to write output WAV file '%s'.\n", output);
            free(samples);
            return 1;
        }

        printf("Successfully modulated '%s' (%zu bytes) into '%s' (%zu samples, %.2f seconds)\n",
               input, input_len, output, sample_len, (double)sample_len / cfg.sample_rate);
        free(samples);
        return 0;
    } 
    else if (strcmp(command, "demodulate") == 0) {
        const char* mode = NULL;
        const char* input = NULL;

        // Configuration defaults
        sw_config_t cfg;
        memset(&cfg, 0, sizeof(cfg));
        cfg.sample_rate = 44100;
        cfg.modulation = 0; // CSS
        cfg.sf = 8;
        cfg.num_subcarriers = 256;
        cfg.cp_length = 64;
        cfg.num_pilots = 8;
        cfg.coding_rate = 0.5f;
        cfg.threshold = 3.0f;
        cfg.equalizer = 0; // ZF
        cfg.carrier_freq = 19000.0f;
        cfg.bandwidth = 2000.0f;
        cfg.symbol_duration = 0.02f;
        cfg.amplitude = 0.8f;
        cfg.ofdm_modulation = 1; // QPSK

        // Parse command options
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
                mode = argv[++i];
            } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
                input = argv[++i];
            } else if (strcmp(argv[i], "--sf") == 0 && i + 1 < argc) {
                cfg.sf = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--fft") == 0 && i + 1 < argc) {
                cfg.num_subcarriers = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--cp") == 0 && i + 1 < argc) {
                cfg.cp_length = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--freq") == 0 && i + 1 < argc) {
                cfg.carrier_freq = (float)atof(argv[++i]);
            } else if (strcmp(argv[i], "--bw") == 0 && i + 1 < argc) {
                cfg.bandwidth = (float)atof(argv[++i]);
            } else if (strcmp(argv[i], "--amp") == 0 && i + 1 < argc) {
                cfg.amplitude = (float)atof(argv[++i]);
            } else if (strcmp(argv[i], "--equalizer") == 0 && i + 1 < argc) {
                const char* eq = argv[++i];
                if (strcmp(eq, "mmse") == 0) {
                    cfg.equalizer = 1;
                } else {
                    cfg.equalizer = 0;
                }
            }
        }

        if (!mode || !input) {
            fprintf(stderr, "Error: Missing required arguments (--mode, --input).\n\n");
            print_usage();
            return 1;
        }

        if (strcmp(mode, "css") == 0) {
            cfg.modulation = 0;
        } else if (strcmp(mode, "ofdm") == 0) {
            cfg.modulation = 1;
        } else {
            fprintf(stderr, "Error: Invalid mode '%s'. Choose 'css' or 'ofdm'.\n", mode);
            return 1;
        }

        // Read input WAV file
        float* samples = NULL;
        size_t num_samples = 0;
        uint32_t sample_rate = 0;

        if (wav_read_mono(input, &samples, &num_samples, &sample_rate) != 0) {
            fprintf(stderr, "Error: Failed to read input WAV file '%s'.\n", input);
            return 1;
        }

        cfg.sample_rate = (int)sample_rate;

        // Debug: call sw_detect_frame
        size_t debug_start = 0;
        float debug_snr = 0.0f;
        int debug_sync = sw_detect_frame(samples, num_samples, cfg, &debug_start, &debug_snr);
        fprintf(stderr, "DEBUG: sw_detect_frame returned %d, frame_start = %zu, snr = %.2f dB\n",
                debug_sync, debug_start, debug_snr);

        // Allocate buffer for demodulated bits
        size_t bit_len = 160000;
        uint8_t* bits = (uint8_t*)malloc(20000 * sizeof(uint8_t));
        if (!bits) {
            fprintf(stderr, "Error: Out of memory.\n");
            free(samples);
            return 1;
        }

        // Demodulate
        int ret;
        if (cfg.modulation == 0) {
            ret = sw_css_demodulate(samples, num_samples, cfg, bits, &bit_len);
        } else {
            ret = sw_ofdm_demodulate(samples, num_samples, cfg, bits, &bit_len);
        }

        free(samples);

        if (ret != SW_OK) {
            fprintf(stderr, "Error: Demodulation failed with code %d\n", ret);
            free(bits);
            return 1;
        }

        size_t frame_len = bit_len / 8;
        if (frame_len < 38) { // Min size: 4 CRC + 2 length + 32 parity = 38 bytes
            fprintf(stderr, "Error: Demodulated frame is too short (%zu bytes).\n", frame_len);
            free(bits);
            return 1;
        }

        // Extract length field
        size_t payload_len = bits[4] | (bits[5] << 8);
        size_t packet_len = 6 + payload_len;

        if (packet_len + 32 > frame_len) {
            fprintf(stderr, "DEBUG: Length field %zu indicates packet size %zu is too large for frame %zu. Retrying CRC match...\n",
                    payload_len, packet_len, frame_len);
            
            // Fallback: try to find length via CRC match
            int crc_matched = 0;
            uint32_t received_crc = bits[0] | (bits[1] << 8) | (bits[2] << 16) | (bits[3] << 24);
            for (size_t l = 1; l <= frame_len - 38; l++) {
                uint32_t calculated_crc;
                sw_crc32(bits + 6, l, &calculated_crc);
                if (calculated_crc == received_crc) {
                    payload_len = l;
                    packet_len = 6 + l;
                    crc_matched = 1;
                    break;
                }
            }
            if (!crc_matched) {
                fprintf(stderr, "Error: CRC matching failed and length field was invalid.\n");
                free(bits);
                return 1;
            }
        }

        // Perform RS decoding
        int errors_corrected = 0;
        ret = sw_rs_decode(bits, &packet_len, bits + packet_len, 32, &errors_corrected);
        if (ret != SW_OK) {
            fprintf(stderr, "Error: Reed-Solomon decoding failed with code %d.\n", ret);
            free(bits);
            return 1;
        }

        // Verify CRC-32
        uint32_t received_crc = bits[0] | (bits[1] << 8) | (bits[2] << 16) | (bits[3] << 24);
        uint32_t calculated_crc;
        sw_crc32(bits + 6, payload_len, &calculated_crc);

        if (received_crc != calculated_crc) {
            fprintf(stderr, "Error: CRC check failed. Received: 0x%08X, Calculated: 0x%08X\n", received_crc, calculated_crc);
            free(bits);
            return 1;
        }

        // Demodulation successful! Output payload to stdout and details to stderr
        fwrite(bits + 6, 1, payload_len, stdout);
        
        // Output trailing newline to stdout if not present in payload
        if (payload_len == 0 || (bits + 6)[payload_len - 1] != '\n') {
            printf("\n");
        }

        fprintf(stderr, "Demodulation successful! (Errors corrected: %d)\n", errors_corrected);

        free(bits);
        return 0;
    }
    else if (strcmp(command, "simulate") == 0) {
        const char* input = NULL;
        const char* output = NULL;
        float snr = 10.0f;
        int has_snr = 0;

        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
                input = argv[++i];
            } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
                output = argv[++i];
            } else if (strcmp(argv[i], "--snr") == 0 && i + 1 < argc) {
                snr = (float)atof(argv[++i]);
                has_snr = 1;
            }
        }

        if (!input || !output || !has_snr) {
            fprintf(stderr, "Error: Missing required arguments (--input, --snr, --output).\n\n");
            print_usage();
            return 1;
        }

        // Read input WAV
        float* samples = NULL;
        size_t num_samples = 0;
        uint32_t sample_rate = 0;

        if (wav_read_mono(input, &samples, &num_samples, &sample_rate) != 0) {
            fprintf(stderr, "Error: Failed to read input WAV file '%s'.\n", input);
            return 1;
        }

        // Add noise
        float* noisy = (float*)malloc(num_samples * sizeof(float));
        if (!noisy) {
            fprintf(stderr, "Error: Out of memory.\n");
            free(samples);
            return 1;
        }

        add_awgn_noise(samples, num_samples, snr, noisy);
        free(samples);

        // Write output WAV
        if (wav_write_mono_i16(output, noisy, num_samples, sample_rate) != 0) {
            fprintf(stderr, "Error: Failed to write output WAV file '%s'.\n", output);
            free(noisy);
            return 1;
        }

        printf("Successfully simulated AWGN channel on '%s' -> '%s' (SNR: %.1f dB)\n", input, output, snr);
        free(noisy);
        return 0;
    }
    else {
        fprintf(stderr, "Error: Unknown command '%s'.\n\n", command);
        print_usage();
        return 1;
    }
}
