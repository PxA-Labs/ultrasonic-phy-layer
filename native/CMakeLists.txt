cmake_minimum_required(VERSION 3.22)
project(soundwave VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Options
option(SW_BUILD_TESTS      "Build C/C++ tests"       ON)
option(SW_BUILD_BENCHMARKS "Build C benchmarks"      OFF)
option(SW_BUILD_FUZZ       "Build fuzz harnesses"    OFF)
option(SW_USE_SANITIZER    "Enable ASan+UBSan"       OFF)
option(SW_BUILD_COVERAGE   "Enable code coverage"    OFF)

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
)

# Static library target
add_library(soundwave STATIC ${SW_SOURCES})
target_include_directories(soundwave PUBLIC include)
target_link_libraries(soundwave PRIVATE kiss_fft miniaudio)

# Shared library target
add_library(soundwave_shared SHARED $<TARGET_OBJECTS:soundwave>)
set_target_properties(soundwave_shared PROPERTIES
    OUTPUT_NAME "soundwave"
    PREFIX "lib"
    SOVERSION 1
    VERSION ${PROJECT_VERSION}
    PUBLIC_HEADER "include/soundwave_api.h"
)
target_link_libraries(soundwave_shared PRIVATE kiss_fft miniaudio)

# Platform-specific audio system libraries
if(WIN32)
    target_link_libraries(soundwave PRIVATE ole32 user32)
    target_link_libraries(soundwave_shared PRIVATE ole32 user32)
elseif(APPLE)
    find_library(AUDIO_TOOLBOX AudioToolbox)
    find_library(CORE_AUDIO CoreAudio)
    if(AUDIO_TOOLBOX)
        target_link_libraries(soundwave PRIVATE ${AUDIO_TOOLBOX})
        target_link_libraries(soundwave_shared PRIVATE ${AUDIO_TOOLBOX})
    endif()
    if(CORE_AUDIO)
        target_link_libraries(soundwave PRIVATE ${CORE_AUDIO})
        target_link_libraries(soundwave_shared PRIVATE ${CORE_AUDIO})
    endif()
    target_link_libraries(soundwave PRIVATE m)
    target_link_libraries(soundwave_shared PRIVATE m)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(soundwave PRIVATE m pthread dl)
    target_link_libraries(soundwave_shared PRIVATE m pthread dl)
endif()

# Sanitizers
if(SW_USE_SANITIZER)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# Code coverage
if(SW_BUILD_COVERAGE AND (CMAKE_C_COMPILER_ID MATCHES "GNU|Clang"))
    add_compile_options(-fprofile-arcs -ftest-coverage -g)
    add_link_options(-fprofile-arcs -ftest-coverage)
endif()

# Subdirectories
if(SW_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(SW_BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

if(SW_BUILD_FUZZ)
    add_subdirectory(Fuzzing)
endif()
