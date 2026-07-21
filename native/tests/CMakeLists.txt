# Test CMake — builds all test executables and registers them with CTest.

# Include catch header directory
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Helper: create a C test executable and register it
function(sw_add_test TEST_NAME TEST_SOURCE)
    add_executable(${TEST_NAME} ${TEST_SOURCE})
    target_link_libraries(${TEST_NAME} PRIVATE soundwave kiss_fft)
    if(NOT WIN32)
        target_link_libraries(${TEST_NAME} PRIVATE m)
    endif()
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()

# Individual DSP tests
sw_add_test(test_crc                 test_crc.c)
sw_add_test(test_rs_encoder          test_rs_encoder.c)
sw_add_test(test_rs_decoder          test_rs_decoder.c)
sw_add_test(test_encoder             test_encoder.c)
sw_add_test(test_modulator           test_modulator.c)
sw_add_test(test_css_modulate        test_css_modulate.c)
sw_add_test(test_css_demodulate      test_css_demodulate.c)
sw_add_test(test_ofdm_modulate       test_ofdm_modulate.c)
sw_add_test(test_ofdm_demodulate     test_ofdm_demodulate.c)
sw_add_test(test_sync                test_sync.c)
sw_add_test(test_cfo                 test_cfo.c)
sw_add_test(test_audio               test_audio.c)
sw_add_test(test_api                 test_api.c)
sw_add_test(test_fft                 test_fft.c)
sw_add_test(test_e2e                 test_e2e.c)
sw_add_test(integration_loopback     integration_loopback.c)

# Catch2 C++ Test Runner Target
add_executable(catch_tests main.cpp)
target_link_libraries(catch_tests PRIVATE soundwave kiss_fft)
if(NOT WIN32)
    target_link_libraries(catch_tests PRIVATE m)
endif()
add_test(NAME catch_tests COMMAND catch_tests)
