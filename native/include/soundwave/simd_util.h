// SIMD utility definitions for ARM NEON and x86 AVX2.
// Implements vector dot products and complex correlation operations.

#ifndef SOUNDWAVE_SIMD_UTIL_H
#define SOUNDWAVE_SIMD_UTIL_H

#include <stddef.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    #include <arm_neon.h>
    #define SW_SIMD_NEON 1
#else
    #define SW_SIMD_NEON 0
#endif

#if defined(__AVX2__)
    #include <immintrin.h>
    #define SW_SIMD_AVX2 1
#elif defined(__SSE4_1__)
    #include <smmintrin.h>
    #define SW_SIMD_SSE 1
#else
    #define SW_SIMD_AVX2 0
    #define SW_SIMD_SSE 0
#endif

// Scalar fallback dot product
static inline float simd_dot_product_scalar(const float* a, const float* b, size_t len) {
    double sum = 0.0;
    for (size_t i = 0; i < len; i++) {
        sum += (double)a[i] * (double)b[i];
    }
    return (float)sum;
}

#if SW_SIMD_NEON
static inline float simd_dot_product_neon(const float* a, const float* b, size_t len) {
    size_t i = 0;
    float32x4_t sum_vec = vdupq_n_f32(0.0f);
    for (; i + 3 < len; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        sum_vec = vmlaq_f32(sum_vec, va, vb);
    }
    float sum_arr[4];
    vst1q_f32(sum_arr, sum_vec);
    float sum = sum_arr[0] + sum_arr[1] + sum_arr[2] + sum_arr[3];
    for (; i < len; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}
#endif

#if SW_SIMD_AVX2
static inline float simd_dot_product_avx2(const float* a, const float* b, size_t len) {
    size_t i = 0;
    __m256 sum_vec = _mm256_setzero_ps();
    for (; i + 7 < len; i += 8) {
        __m256 va = _mm256_loadu_ps(a + i);
        __m256 vb = _mm256_loadu_ps(b + i);
        sum_vec = _mm256_fmadd_ps(va, vb, sum_vec);
    }
    float sum_arr[8];
    _mm256_storeu_ps(sum_arr, sum_vec);
    float sum = sum_arr[0] + sum_arr[1] + sum_arr[2] + sum_arr[3] +
                sum_arr[4] + sum_arr[5] + sum_arr[6] + sum_arr[7];
    for (; i < len; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}
#endif

#if SW_SIMD_SSE
static inline float simd_dot_product_sse(const float* a, const float* b, size_t len) {
    size_t i = 0;
    __m128 sum_vec = _mm_setzero_ps();
    for (; i + 3 < len; i += 4) {
        __m128 va = _mm_loadu_ps(a + i);
        __m128 vb = _mm_loadu_ps(b + i);
        sum_vec = _mm_add_ps(sum_vec, _mm_mul_ps(va, vb));
    }
    float sum_arr[4];
    _mm_storeu_ps(sum_arr, sum_vec);
    float sum = sum_arr[0] + sum_arr[1] + sum_arr[2] + sum_arr[3];
    for (; i < len; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}
#endif

static inline float simd_dot_product(const float* a, const float* b, size_t len) {
#if SW_SIMD_AVX2
    return simd_dot_product_avx2(a, b, len);
#elif SW_SIMD_SSE
    return simd_dot_product_sse(a, b, len);
#elif SW_SIMD_NEON
    return simd_dot_product_neon(a, b, len);
#else
    return simd_dot_product_scalar(a, b, len);
#endif
}

// --- Complex Correlation / Complex Dot Product ---

static inline void simd_complex_dot_product_scalar(const float* a_r, const float* a_i,
                                                   const float* b_r, const float* b_i,
                                                   size_t len, double* out_r, double* out_i) {
    double s_r = 0.0;
    double s_i = 0.0;
    for (size_t i = 0; i < len; i++) {
        s_r += (double)a_r[i] * (double)b_r[i] + (double)a_i[i] * (double)b_i[i];
        s_i += (double)a_i[i] * (double)b_r[i] - (double)a_r[i] * (double)b_i[i];
    }
    *out_r = s_r;
    *out_i = s_i;
}

#if SW_SIMD_NEON
static inline void simd_complex_dot_product_neon(const float* a_r, const float* a_i,
                                                 const float* b_r, const float* b_i,
                                                 size_t len, double* out_r, double* out_i) {
    size_t i = 0;
    float32x4_t sum_r = vdupq_n_f32(0.0f);
    float32x4_t sum_i = vdupq_n_f32(0.0f);

    for (; i + 3 < len; i += 4) {
        float32x4_t va_r = vld1q_f32(a_r + i);
        float32x4_t va_i = vld1q_f32(a_i + i);
        float32x4_t vb_r = vld1q_f32(b_r + i);
        float32x4_t vb_i = vld1q_f32(b_i + i);

        sum_r = vmlaq_f32(sum_r, va_r, vb_r);
        sum_r = vmlaq_f32(sum_r, va_i, vb_i);

        sum_i = vmlaq_f32(sum_i, va_i, vb_r);
        sum_i = vmlsq_f32(sum_i, va_r, vb_i);
    }

    float arr_r[4], arr_i[4];
    vst1q_f32(arr_r, sum_r);
    vst1q_f32(arr_i, sum_i);

    double s_r = (double)arr_r[0] + (double)arr_r[1] + (double)arr_r[2] + (double)arr_r[3];
    double s_i = (double)arr_i[0] + (double)arr_i[1] + (double)arr_i[2] + (double)arr_i[3];

    for (; i < len; i++) {
        s_r += (double)a_r[i] * (double)b_r[i] + (double)a_i[i] * (double)b_i[i];
        s_i += (double)a_i[i] * (double)b_r[i] - (double)a_r[i] * (double)b_i[i];
    }

    *out_r = s_r;
    *out_i = s_i;
}
#endif

#if SW_SIMD_AVX2
static inline void simd_complex_dot_product_avx2(const float* a_r, const float* a_i,
                                                 const float* b_r, const float* b_i,
                                                 size_t len, double* out_r, double* out_i) {
    size_t i = 0;
    __m256 sum_r = _mm256_setzero_ps();
    __m256 sum_i = _mm256_setzero_ps();

    for (; i + 7 < len; i += 8) {
        __m256 va_r = _mm256_loadu_ps(a_r + i);
        __m256 va_i = _mm256_loadu_ps(a_i + i);
        __m256 vb_r = _mm256_loadu_ps(b_r + i);
        __m256 vb_i = _mm256_loadu_ps(b_i + i);

        sum_r = _mm256_fmadd_ps(va_r, vb_r, sum_r);
        sum_r = _mm256_fmadd_ps(va_i, vb_i, sum_r);

        sum_i = _mm256_fmadd_ps(va_i, vb_r, sum_i);
        sum_i = _mm256_fnmadd_ps(va_r, vb_i, sum_i);
    }

    float arr_r[8], arr_i[8];
    _mm256_storeu_ps(arr_r, sum_r);
    _mm256_storeu_ps(arr_i, sum_i);

    double s_r = 0.0, s_i = 0.0;
    for (int k = 0; k < 8; k++) {
        s_r += arr_r[k];
        s_i += arr_i[k];
    }

    for (; i < len; i++) {
        s_r += (double)a_r[i] * (double)b_r[i] + (double)a_i[i] * (double)b_i[i];
        s_i += (double)a_i[i] * (double)b_r[i] - (double)a_r[i] * (double)b_i[i];
    }

    *out_r = s_r;
    *out_i = s_i;
}
#endif

static inline void simd_complex_dot_product(const float* a_r, const float* a_i,
                                            const float* b_r, const float* b_i,
                                            size_t len, double* out_r, double* out_i) {
#if SW_SIMD_AVX2
    simd_complex_dot_product_avx2(a_r, a_i, b_r, b_i, len, out_r, out_i);
#elif SW_SIMD_NEON
    simd_complex_dot_product_neon(a_r, a_i, b_r, b_i, len, out_r, out_i);
#else
    simd_complex_dot_product_scalar(a_r, a_i, b_r, b_i, len, out_r, out_i);
#endif
}

#endif // SOUNDWAVE_SIMD_UTIL_H
