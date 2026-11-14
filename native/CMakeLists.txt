cmake_minimum_required(VERSION 3.22)
project(soundwave VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Options
option(SW_BUILD_TESTS      "Build C/C++ tests"       ON)
option(SW_BUILD_BENCHMARKS "Build C benchmarks"      OFF)
option(SW_BUILD_COVERAGE   "Enable code coverage"    OFF)

# Memory-safety options (issue #28). See docs/DEVELOPER_GUIDE.md "Sanitizers & Fuzzing".
option(SW_ENABLE_ASAN      "Enable AddressSanitizer (+LeakSanitizer where supported)" OFF)
option(SW_ENABLE_UBSAN     "Enable UndefinedBehaviorSanitizer (fatal on first report)" OFF)
option(SW_ENABLE_FUZZER    "Build libFuzzer harnesses (requires LLVM Clang)"          OFF)
option(SW_FUZZ_SMOKE       "Build fuzz harnesses as CTest smoke tests (no libFuzzer)"  ON)
set(SW_FUZZ_SMOKE_RUNS "500" CACHE STRING "Random inputs per fuzz smoke test")
# Deprecated aliases kept for existing scripts/presets.
option(SW_USE_SANITIZER    "Deprecated: same as SW_ENABLE_ASAN + SW_ENABLE_UBSAN" OFF)
option(SW_BUILD_FUZZ       "Deprecated: same as SW_ENABLE_FUZZER"                 OFF)
if(SW_USE_SANITIZER)
    set(SW_ENABLE_ASAN ON)
    set(SW_ENABLE_UBSAN ON)
endif()
if(SW_BUILD_FUZZ)
    set(SW_ENABLE_FUZZER ON)
endif()

# Sanitizers (must be configured before any add_library/add_executable)
if(SW_ENABLE_ASAN)
    if(MSVC)
        # MSVC ASan is incompatible with /RTC and incremental linking.
        foreach(flag_var CMAKE_C_FLAGS_DEBUG CMAKE_CXX_FLAGS_DEBUG)
            string(REGEX REPLACE "/RTC[1csu]+" "" ${flag_var} "${${flag_var}}")
        endforeach()
        add_compile_options(/fsanitize=address /Zi)
        add_link_options(/INCREMENTAL:NO)
    elseif(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
        add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
        add_link_options(-fsanitize=address)
    else()
        message(WARNING "SW_ENABLE_ASAN: unsupported compiler ${CMAKE_C_COMPILER_ID}; ignored")
    endif()
endif()

if(SW_ENABLE_UBSAN)
    if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
        add_compile_options(-fsanitize=undefined -fno-sanitize-recover=undefined
                            -fno-omit-frame-pointer -g)
        add_link_options(-fsanitize=undefined)
        if(CMAKE_C_COMPILER_ID MATCHES "Clang")
            # Not UB under IEEE-754, but in DSP code a /0 means a missing guard
            # and silently propagates Inf/NaN into decoded data.
            add_compile_options(-fsanitize=float-divide-by-zero
                                -fno-sanitize-recover=float-divide-by-zero)
            add_link_options(-fsanitize=float-divide-by-zero)
        endif()
    else()
        message(WARNING "SW_ENABLE_UBSAN: unsupported compiler ${CMAKE_C_COMPILER_ID}; ignored")
    endif()
endif()

if(SW_ENABLE_FUZZER)
    if(NOT CMAKE_C_COMPILER_ID STREQUAL "Clang")
        message(FATAL_ERROR "SW_ENABLE_FUZZER requires LLVM Clang with libFuzzer "
                            "(found ${CMAKE_C_COMPILER_ID}; AppleClang ships no libFuzzer). "
                            "Use -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++.")
    endif()
    # Instrument the library for coverage feedback; harnesses link the runtime.
    add_compile_options(-fsanitize=fuzzer-no-link)
endif()

# Code coverage (Must be before any add_library or add_executable)
if(SW_BUILD_COVERAGE AND (CMAKE_C_COMPILER_ID MATCHES "GNU|Clang"))
    add_compile_options(--coverage -g)
    add_link_options(--coverage)
endif()

# SIMD architecture options
if(ANDROID)
    # Android ABIs (issue #87). Never assume AVX2 here: the x86_64 Android ABI
    # only guarantees SSE4.2, and most emulator images lack AVX2.
    if(ANDROID_ABI STREQUAL "arm64-v8a")
        # NEON is mandatory on AArch64; fail the build if the NEON path in
        # simd_util.h is not selected.
        add_compile_definitions(SW_REQUIRE_NEON=1)
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
        # NDK r21+ enables NEON for armv7 by default (ANDROID_ARM_NEON=ON).
        add_compile_definitions(SW_REQUIRE_NEON=1)
    elseif(ANDROID_ABI STREQUAL "x86_64")
        add_compile_options(-msse4.2)
    endif()
    message(STATUS "soundwave: Android ABI=${ANDROID_ABI} platform=${ANDROID_PLATFORM}")
elseif(CMAKE_C_COMPILER_ID MATCHES "MSVC")
    add_compile_options(/arch:AVX2)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    add_compile_options(-mavx2 -mfma)
endif()


# Version definitions
set(SW_VERSION_STRING "${PROJECT_VERSION}")
add_compile_definitions(SW_VERSION="${SW_VERSION_STRING}")

# Public include directory
include_directories(include)

# Vendored KissFFT static library
add_library(kiss_fft STATIC
    vendor/kissfft/kiss_fft.c
    vendor/kissfft/kiss_fftr.c
)
target_include_directories(kiss_fft PUBLIC vendor/kissfft)

# Vendored miniaudio interface library
add_library(miniaudio INTERFACE)
target_include_directories(miniaudio INTERFACE vendor/miniaudio)

# Source files for libsoundwave
set(SW_SOURCES
    src/encoder.c
    src/modulator.c
    src/synchronizer.c
    src/demodulator.c
    src/api/soundwave_api.c
    src/api/ffi_helpers.c
    src/audio/audio_io.c
    src/agc/agc.c
    src/chanest/chanest.c
    src/crc/crc32.c
    src/css/css_modulate.c
    src/css/css_demodulate.c
    src/equalizer/equalizer.c
    src/fec/fec.c
    src/ofdm/ofdm_modulate.c
    src/ofdm/ofdm_demodulate.c
    src/packet/packet.c
    src/rs/rs_encoder.c
    src/rs/rs_decoder.c
    src/sync/sync_cfo.c
    src/sync/sync_frame.c
    src/sync/sync_xcorr.c
)

# Object library target containing common compiled objects
add_library(soundwave OBJECT ${SW_SOURCES})
target_include_directories(soundwave PUBLIC include)
target_compile_definitions(soundwave PRIVATE SW_BUILD_DLL)
target_link_libraries(soundwave PRIVATE kiss_fft miniaudio)

# Static library target
add_library(soundwave_static STATIC $<TARGET_OBJECTS:soundwave>)
set_target_properties(soundwave_static PROPERTIES OUTPUT_NAME "soundwave")
target_include_directories(soundwave_static PUBLIC include)
target_link_libraries(soundwave_static PRIVATE kiss_fft miniaudio)

# Shared library target
add_library(soundwave_shared SHARED $<TARGET_OBJECTS:soundwave>)
set_target_properties(soundwave_shared PROPERTIES
    OUTPUT_NAME "soundwave"
    PREFIX "lib"
    PUBLIC_HEADER "include/soundwave_api.h"
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
if(NOT ANDROID)
    # Android loads libraries by plain file name (System.loadLibrary /
    # DynamicLibrary.open("libsoundwave.so")), so no versioned SONAME there.
    set_target_properties(soundwave_shared PROPERTIES
        SOVERSION 1
        VERSION ${PROJECT_VERSION}
    )
endif()
target_include_directories(soundwave_shared PUBLIC include)
target_compile_definitions(soundwave_shared PRIVATE SW_BUILD_DLL)
target_link_libraries(soundwave_shared PRIVATE kiss_fft miniaudio)

# Platform-specific audio system libraries
if(WIN32)
    target_link_libraries(soundwave PRIVATE ole32 user32)
    target_link_libraries(soundwave_static PRIVATE ole32 user32)
    target_link_libraries(soundwave_shared PRIVATE ole32 user32)
elseif(APPLE)
    find_library(AUDIO_TOOLBOX AudioToolbox)
    find_library(CORE_AUDIO CoreAudio)
    if(AUDIO_TOOLBOX)
        target_link_libraries(soundwave PRIVATE ${AUDIO_TOOLBOX})
        target_link_libraries(soundwave_static PRIVATE ${AUDIO_TOOLBOX})
        target_link_libraries(soundwave_shared PRIVATE ${AUDIO_TOOLBOX})
    endif()
    if(CORE_AUDIO)
        target_link_libraries(soundwave PRIVATE ${CORE_AUDIO})
        target_link_libraries(soundwave_static PRIVATE ${CORE_AUDIO})
        target_link_libraries(soundwave_shared PRIVATE ${CORE_AUDIO})
    endif()
    target_link_libraries(soundwave PRIVATE m)
    target_link_libraries(soundwave_static PRIVATE m)
    target_link_libraries(soundwave_shared PRIVATE m)
elseif(ANDROID)
    # pthread is part of Bionic libc. miniaudio dlopen()s libaaudio.so
    # (API 26+) and falls back to libOpenSLES.so, so neither is linked here.
    target_link_libraries(soundwave PRIVATE m dl log)
    target_link_libraries(soundwave_static PRIVATE m dl log)
    target_link_libraries(soundwave_shared PRIVATE m dl log)
    # 16 KB page alignment, required for Play Store uploads targeting
    # Android 15+ devices (default only from NDK r28).
    target_link_options(soundwave_shared PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX AND NOT APPLE)
    target_link_libraries(soundwave PRIVATE m pthread dl)
    target_link_libraries(soundwave_static PRIVATE m pthread dl)
    target_link_libraries(soundwave_shared PRIVATE m pthread dl)
endif()



# Subdirectories
if(SW_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(SW_BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

if(SW_ENABLE_FUZZER OR (SW_BUILD_TESTS AND SW_FUZZ_SMOKE))
    add_subdirectory(Fuzzing)
endif()

# Standalone CLI Developer Tool (host-only; not useful inside an APK)
if(NOT ANDROID)
    add_executable(soundwave_cli
        tools/soundwave_cli/main.c
        tools/soundwave_cli/wav_util.c
        tools/soundwave_cli/frame_format.c
    )
    target_link_libraries(soundwave_cli PRIVATE soundwave_static)
    target_include_directories(soundwave_cli PRIVATE tools/soundwave_cli)
    set_target_properties(soundwave_cli PROPERTIES OUTPUT_NAME "soundwave-cli")
endif()
