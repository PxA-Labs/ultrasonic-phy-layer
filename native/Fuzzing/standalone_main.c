// Standalone driver for libFuzzer-style harnesses, used where libFuzzer is not
// available (GCC, AppleClang, MSVC) and for the CTest fuzz smoke tests.
//
// Usage: fuzz_<name> [-runs=N] [-seed=S] [-max_len=L] [file ...]
//   * every file argument is replayed once (e.g. a crash reproducer from CI);
//   * then N pseudo-random inputs are generated from seed S.
// Flags use libFuzzer spelling so commands transfer between the two modes.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size);

// xorshift64*: tiny, deterministic, good enough for input generation.
static uint64_t rng_state;

static uint64_t rng_next(void) {
    rng_state ^= rng_state >> 12;
    rng_state ^= rng_state << 25;
    rng_state ^= rng_state >> 27;
    return rng_state * 0x2545F4914F6CDD1DULL;
}

static int replay_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", path);
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return -1;
    }
    long len = ftell(f);
    if (len < 0 || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    uint8_t* buf = (uint8_t*)malloc(len > 0 ? (size_t)len : 1);
    if (!buf) {
        fclose(f);
        return -1;
    }
    size_t got = fread(buf, 1, (size_t)len, f);
    fclose(f);
    printf("replay %s (%zu bytes)\n", path, got);
    LLVMFuzzerTestOneInput(buf, got);
    free(buf);
    return 0;
}

// Fill with a mix of byte patterns that tend to reach interesting paths:
// uniform noise, runs of a constant, and IEEE-754 specials (NaN/Inf/huge).
static void fill_input(uint8_t* buf, size_t len) {
    static const uint32_t specials[] = {
        0x7FC00000u, /* NaN   */ 0x7F800000u, /* +Inf */ 0xFF800000u, /* -Inf */
        0x7F7FFFFFu, /* FLT_MAX */ 0x00000001u, /* denormal */ 0x00000000u,
        0x3F800000u, /* 1.0 */ 0xBF800000u, /* -1.0 */
    };
    size_t i = 0;
    while (i < len) {
        uint64_t r = rng_next();
        unsigned mode = (unsigned)(r & 7u);
        size_t run = 1 + (size_t)((r >> 8) % 64);
        for (size_t j = 0; j < run && i < len; j++, i++) {
            if (mode == 0) {
                buf[i] = (uint8_t)(r >> 16);
            } else if (mode == 1 && i + 4 <= len) {
                uint32_t v = specials[(r >> 20) % (sizeof specials / sizeof *specials)];
                memcpy(buf + i, &v, 4);
                i += 3;
            } else {
                buf[i] = (uint8_t)rng_next();
            }
        }
    }
}

int main(int argc, char** argv) {
    unsigned long runs = 1000;
    unsigned long long seed = 1;
    size_t max_len = 8192;
    int replayed = 0;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-runs=", 6) == 0) {
            runs = strtoul(argv[i] + 6, NULL, 10);
        } else if (strncmp(argv[i], "-seed=", 6) == 0) {
            seed = strtoull(argv[i] + 6, NULL, 10);
        } else if (strncmp(argv[i], "-max_len=", 9) == 0) {
            max_len = (size_t)strtoul(argv[i] + 9, NULL, 10);
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "ignoring unsupported flag %s\n", argv[i]);
        } else {
            if (replay_file(argv[i]) != 0) return 1;
            replayed++;
        }
    }
    if (max_len == 0) max_len = 1;
    rng_state = seed ? seed : 0x9E3779B97F4A7C15ULL;

    uint8_t* buf = (uint8_t*)malloc(max_len);
    if (!buf) return 1;

    // Always exercise the empty and tiny inputs first.
    LLVMFuzzerTestOneInput(buf, 0);
    for (unsigned long n = 0; n < runs; n++) {
        size_t len = (size_t)(rng_next() % (max_len + 1));
        fill_input(buf, len);
        // Exact-size heap copy so overreads hit ASan redzones / guard pages.
        uint8_t* exact = (uint8_t*)malloc(len ? len : 1);
        if (!exact) break;
        memcpy(exact, buf, len);
        LLVMFuzzerTestOneInput(exact, len);
        free(exact);
    }
    free(buf);
    printf("OK: %d replayed, %lu random inputs (seed %llu)\n", replayed, runs, seed);
    return 0;
}
