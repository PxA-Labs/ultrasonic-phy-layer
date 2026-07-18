cmake_minimum_required(VERSION 3.16)
project(soundwave VERSION 1.0.0 LANGUAGES C)

# Options
option(SW_BUILD_TESTS   "Build C tests"    ON)
option(SW_BUILD_FUZZ    "Build fuzz harnesses" OFF)
option(SW_USE_SANITIZER "Enable ASan+UBSan" OFF)

# Configuration
set(SW_VERSION_STRING "${PROJECT_VERSION}")
add_compile_definitions(SW_VERSION="${SW_VERSION_STRING}")

# Include paths
include_directories(include)
include_directories(${CMAKE_BINARY_DIR}/_deps/kissfft-src)

# Fetch kissfft from GitHub
include(FetchContent)
FetchContent_Declare(
    kissfft
    GIT_REPOSITORY https://github.com/mborgerding/kissfft.git
    GIT_TAG        v131.1.0
    SOURCE_DIR     ${CMAKE_BINARY_DIR}/_deps/kissfft-src
)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(KISSFFT_SHARED OFF CACHE BOOL "" FORCE)
set(KISSFFT_STATIC ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(kissfft)

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
set_target_properties(soundwave PROPERTIES
    PUBLIC_HEADER "include/soundwave_api.h"
    SOVERSION 1
    VERSION ${PROJECT_VERSION}
)

if(SW_USE_SANITIZER)
    target_compile_options(soundwave PRIVATE -fsanitize=address,undefined -g)
    target_link_options(soundwave PRIVATE -fsanitize=address,undefined)
endif()

# Tests
if(SW_BUILD_TESTS)
    add_subdirectory(tests)
endif()

# Fuzzing
if(SW_BUILD_FUZZ)
    add_subdirectory(Fuzzing)
endif()
