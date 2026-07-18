cmake_minimum_required(VERSION 3.16)
project(soundwave VERSION 1.0.0 LANGUAGES C)

# Options
option(SW_BUILD_TESTS      "Build C tests"           ON)
option(SW_BUILD_BENCHMARKS "Build C benchmarks"      OFF)
option(SW_BUILD_FUZZ       "Build fuzz harnesses"    OFF)
option(SW_USE_SANITIZER    "Enable ASan+UBSan"       OFF)
option(SW_BUILD_COVERAGE   "Enable code coverage"    OFF)

# Configuration
set(SW_VERSION_STRING "${PROJECT_VERSION}")
add_compile_definitions(SW_VERSION="${SW_VERSION_STRING}")

# Include paths
include_directories(include)

# Fetch kissfft from GitHub (populate manually, define our own target)
include(FetchContent)
FetchContent_Declare(
    kissfft
    GIT_REPOSITORY https://github.com/mborgerding/kissfft.git
    GIT_TAG        v131
)
FetchContent_GetProperties(kissfft)
if(NOT kissfft_POPULATED)
    FetchContent_Populate(kissfft)
    add_library(kissfft STATIC
        ${kissfft_SOURCE_DIR}/kiss_fft.c
        ${kissfft_SOURCE_DIR}/tools/kiss_fftr.c
    )
    target_include_directories(kissfft PUBLIC ${kissfft_SOURCE_DIR})
endif()
include_directories(${kissfft_SOURCE_DIR})

# Public API library
set(SW_SOURCES
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

add_library(soundwave SHARED ${SW_SOURCES})
target_link_libraries(soundwave PRIVATE kissfft)
if(WIN32)
    target_compile_definitions(soundwave PRIVATE SW_BUILD_DLL)
else()
    target_link_libraries(soundwave PRIVATE m)
endif()
set_target_properties(soundwave PROPERTIES
    PUBLIC_HEADER "include/soundwave_api.h"
    SOVERSION 1
    VERSION ${PROJECT_VERSION}
)

if(SW_USE_SANITIZER)
    target_compile_options(soundwave PRIVATE -fsanitize=address,undefined -g)
    target_link_options(soundwave PRIVATE -fsanitize=address,undefined)
endif()

if(SW_BUILD_COVERAGE AND (CMAKE_C_COMPILER_ID MATCHES "GNU|Clang"))
    target_compile_options(soundwave PRIVATE -fprofile-arcs -ftest-coverage -g)
    target_link_options(soundwave PRIVATE -fprofile-arcs -ftest-coverage)
endif()

# Tests
if(SW_BUILD_TESTS)
    add_subdirectory(tests)
endif()

# Benchmarks
if(SW_BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

# Fuzzing
if(SW_BUILD_FUZZ)
    add_subdirectory(Fuzzing)
endif()
