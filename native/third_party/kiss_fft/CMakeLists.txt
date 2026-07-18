# CMake build for vendored kiss_fft library.
# KissFFT: a mixed-radix Fast Fourier Transform library.

add_library(kiss_fft STATIC
    kiss_fft.c
    tools/kiss_fftr.c)
target_include_directories(kiss_fft PUBLIC .)
