#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include "soundwave_api.h"
#include "wav_util.h"
#include "frame_format.h"

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
    fprintf(stderr, "  --sf <sf>                  CSS spreading factor, bits per chirp (6..10; default 8)\n");
    fprintf(stderr, "  --fft <size>               FFT size for OFDM (256, 512, 1024, 2048; default 256)\n");
    fprintf(stderr, "  --cp <length>              Cyclic prefix length for OFDM (default 64)\n");
    fprintf(stderr, "  --freq <freq_hz>           Carrier frequency in Hz (default 19000.0; OFDM band centre)\n");
    fprintf(stderr, "  --bw <bw_hz>               Bandwidth in Hz (default 2000.0; OFDM band = freq +- bw/2)\n");
    fprintf(stderr, "  --ofdm-mod <bpsk|qpsk>     OFDM subcarrier mapping (default qpsk)\n");
    fprintf(stderr, "  --no-rs                    Frames without Reed-Solomon parity (app setting enable_rs = off)\n");
    fprintf(stderr, "\nFrame format (same as the app): [CRC-32 LE][payload 1..%d B][RS parity 32 B]\n",
            SW_FRAME_MAX_PAYLOAD);
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
        int enable_rs = 1;

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
            } else if (strcmp(argv[i], "--ofdm-mod") == 0 && i + 1 < argc) {
                cfg.ofdm_modulation = strcmp(argv[++i], "bpsk") == 0 ? 0 : 1;
            } else if (strcmp(argv[i], "--no-rs") == 0) {
                enable_rs = 0;
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
        if (input_len > SW_FRAME_MAX_PAYLOAD) {
            fprintf(stderr, "Error: Input text is too long (max %d bytes).\n", SW_FRAME_MAX_PAYLOAD);
            return 1;
        }

        // Frame: [CRC-32 LE][payload][RS parity] -- frame_format.h
        uint8_t frame[SW_FRAME_MAX_LEN];
        size_t frame_len = sw_frame_encode((const uint8_t*)input, input_len, enable_rs,
                                           frame, sizeof frame);
        if (frame_len == 0) {
            fprintf(stderr, "Error: Frame encoding (CRC-32 / Reed-Solomon) failed.\n");
            return 1;
        }
        int ret;

        // Modulate signal
        size_t max_samples = 4000000;
        float* samples = (float*)malloc(max_samples * sizeof(float));
        if (!samples) {
            fprintf(stderr, "Error: Out of memory.\n");
            return 1;
        }
        size_t sample_len = max_samples;

        if (cfg.modulation == 0) {
            ret = sw_css_modulate(frame, frame_len * 8, cfg, samples, &sample_len);
        } else {
            ret = sw_ofdm_modulate(frame, frame_len * 8, cfg, samples, &sample_len);
        }

        if (ret != SW_OK) {
            fprintf(stderr, "Error: Modulation failed with code %d\n", ret);
            free(samples);
            return 1;
        }

        // The modulators guarantee max |sample| <= --amp (<= 1), so the
        // samples go to 16-bit PCM unscaled; no rescaling here. Report the
        // peak and treat a violation as the bug it would be.
        float peak = 0.0f;
        for (size_t i = 0; i < sample_len; i++) {
            float abs_val = fabsf(samples[i]);
            if (abs_val > peak) peak = abs_val;
        }
        fprintf(stderr, "DEBUG: Modulated signal peak amplitude = %.4f\n", peak);
        if (!(peak <= 1.0f)) {
            fprintf(stderr, "Error: Modulator output peak %.4f exceeds full scale.\n", peak);
            free(samples);
            return 1;
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
        int enable_rs = 1;

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
            } else if (strcmp(argv[i], "--ofdm-mod") == 0 && i + 1 < argc) {
                cfg.ofdm_modulation = strcmp(argv[++i], "bpsk") == 0 ? 0 : 1;
            } else if (strcmp(argv[i], "--no-rs") == 0) {
                enable_rs = 0;
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
        size_t bit_len = (size_t)1 << 20; // 1 Mbit: minutes of audio at any setting
        uint8_t* bits = (uint8_t*)malloc(bit_len / 8);
        if (!bits) {
            fprintf(stderr, "Error: Out of memory.\n");
            free(samples);
            return 1;
        }

        // Demodulate from the detected frame start, as the app's RxEngine does
        // (the CSS demodulator expects the preamble at the buffer start).
        const float* frame_samples = samples;
        size_t frame_count = num_samples;
        if (debug_sync == SW_OK && debug_start < num_samples) {
            frame_samples = samples + debug_start;
            frame_count = num_samples - debug_start;
        }
        int ret;
        if (cfg.modulation == 0) {
            ret = sw_css_demodulate(frame_samples, frame_count, cfg, bits, &bit_len);
        } else {
            ret = sw_ofdm_demodulate(frame_samples, frame_count, cfg, bits, &bit_len);
        }

        free(samples);

        if (ret != SW_OK) {
            fprintf(stderr, "Error: Demodulation failed with code %d\n", ret);
            free(bits);
            return 1;
        }

        // Frame: [CRC-32 LE][payload][RS parity] with no length field; take
        // the shortest length whose RS decode and CRC verify (frame_format.h).
        uint8_t work[SW_FRAME_MAX_LEN];
        size_t payload_off = 0, payload_len = 0, frame_len = 0;
        int errors_corrected = 0;
        if (!sw_frame_decode(bits, bit_len / 8, enable_rs, work, &payload_off, &payload_len,
                             &frame_len, &errors_corrected)) {
            fprintf(stderr, "Error: No frame length passes %sCRC-32 (%zu demodulated bytes).\n",
                    enable_rs ? "Reed-Solomon decoding and " : "", bit_len / 8);
            free(bits);
            return 1;
        }
        fprintf(stderr, "DEBUG: frame length %zu bytes, payload %zu bytes\n", frame_len, payload_len);

        // Demodulation successful! Output payload to stdout and details to stderr
        fwrite(work + payload_off, 1, payload_len, stdout);

        // Output trailing newline to stdout if not present in payload
        if (work[payload_off + payload_len - 1] != '\n') {
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
