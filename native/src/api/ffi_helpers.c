// FFI helpers — buffer allocation for dart:ffi zero-copy interop.

#include "soundwave_api.h"
#include <stdlib.h>
#include <string.h>

SW_API float* sw_alloc_float(int n) {
    return (float*)calloc((size_t)n, sizeof(float));
}

SW_API double* sw_alloc_double(int n) {
    return (double*)calloc((size_t)n, sizeof(double));
}

SW_API uint8_t* sw_alloc_uint8(int n) {
    return (uint8_t*)calloc((size_t)n, sizeof(uint8_t));
}

SW_API void sw_free(void* ptr) {
    free(ptr);
}
