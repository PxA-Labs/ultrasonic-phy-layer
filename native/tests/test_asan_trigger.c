// Sanitizer canary (issue #28). Built only when SW_ENABLE_ASAN=ON. Each mode
// performs a deliberate memory error, and the CTest entry passes only if the
// AddressSanitizer/LeakSanitizer report appears in the output. If ASan were
// silently not linked or not instrumenting, no report is printed and the test
// fails, so a green sanitizer job proves the sanitizer is really active.
//
// Usage: test_asan_trigger <overflow|use-after-free|leak>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef SW_TEST_ASAN_TRIGGER
#error "test_asan_trigger.c must be compiled with -DSW_TEST_ASAN_TRIGGER"
#endif

// volatile sink defeats dead-store elimination of the bad accesses.
static volatile int g_sink;

static void heap_overflow(void) {
    int* buf = (int*)malloc(8 * sizeof(int));
    if (!buf) return;
    memset(buf, 0, 8 * sizeof(int));
    volatile int idx = 8; // one past the end
    buf[idx] = 42;
    g_sink = buf[0];
    free(buf);
}

static void use_after_free(void) {
    int* buf = (int*)malloc(8 * sizeof(int));
    if (!buf) return;
    buf[0] = 7;
    free(buf);
    g_sink = *(volatile int*)buf;
}

static void leak(void) {
    void* volatile p = malloc(64);
    p = NULL; // lose the only reference; LeakSanitizer reports at exit
    (void)p;
}

int main(int argc, char** argv) {
    const char* mode = argc > 1 ? argv[1] : "overflow";
    if (strcmp(mode, "overflow") == 0) heap_overflow();
    else if (strcmp(mode, "use-after-free") == 0) use_after_free();
    else if (strcmp(mode, "leak") == 0) leak();
    else {
        fprintf(stderr, "unknown mode %s\n", mode);
        return 0; // no sanitizer report -> CTest failure
    }
    printf("sanitizer did NOT trigger for %s\n", mode);
    return 0;
}
