# Test CMake — builds all test executables and registers them with CTest.

# Include catch header directory
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Helper: create a C test executable and register it
function(sw_add_test TEST_NAME TEST_SOURCE)
    add_executable(${TEST_NAME} ${TEST_SOURCE})
    target_link_libraries(${TEST_NAME} PRIVATE soundwave kiss_fft miniaudio)
    if(NOT WIN32)
        target_link_libraries(${TEST_NAME} PRIVATE m)
    else()
        target_link_libraries(${TEST_NAME} PRIVATE ole32 user32)
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
sw_add_test(test_css                 test_css.c)
sw_add_test(test_ofdm_modulate       test_ofdm_modulate.c)
sw_add_test(test_ofdm_demodulate     test_ofdm_demodulate.c)
sw_add_test(test_sync                test_sync.c)
sw_add_test(test_cfo                 test_cfo.c)
sw_add_test(test_audio               test_audio.c)
sw_add_test(test_api                 test_api.c)
sw_add_test(test_fft                 test_fft.c)
sw_add_test(test_agc                 test_agc.c)
sw_add_test(test_e2e                 test_e2e.c)
sw_add_test(integration_loopback     integration_loopback.c)
sw_add_test(test_ber                 test_ber.c)
sw_add_test(test_memsafety           test_memsafety.c)
sw_add_test(test_xcorr               test_xcorr.c)
sw_add_test(test_constellation       test_constellation.c)
sw_add_test(test_ofdm_spectrum      test_ofdm_spectrum.c)

# Sanitizer canary (issue #28): deliberate memory errors that ASan must report.
# A silently missing sanitizer prints no report, so the test fails.
if(SW_ENABLE_ASAN)
    add_executable(test_asan_trigger test_asan_trigger.c)
    target_compile_definitions(test_asan_trigger PRIVATE SW_TEST_ASAN_TRIGGER)
    set(SW_ASAN_TRIGGER_MODES overflow use-after-free)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        list(APPEND SW_ASAN_TRIGGER_MODES leak) # LeakSanitizer is Linux-only
    endif()
    foreach(mode ${SW_ASAN_TRIGGER_MODES})
        add_test(NAME asan_trigger_${mode} COMMAND test_asan_trigger ${mode})
        # Pass only if the sanitizer actually reported the error. abort_on_error=0
        # makes ASan exit instead of raising SIGABRT (CTest counts signals as
        # failures), and PASS_REGULAR_EXPRESSION ignores the exit code.
        set_tests_properties(asan_trigger_${mode} PROPERTIES
            ENVIRONMENT "ASAN_OPTIONS=abort_on_error=0:detect_leaks=1"
            PASS_REGULAR_EXPRESSION "ERROR: (AddressSanitizer|LeakSanitizer)"
            LABELS "sanitizer")
    endforeach()
endif()

# Catch2 C++ Test Runner Target
add_executable(catch_tests main.cpp)
target_link_libraries(catch_tests PRIVATE soundwave kiss_fft miniaudio)
if(NOT WIN32)
    target_link_libraries(catch_tests PRIVATE m)
else()
    target_link_libraries(catch_tests PRIVATE ole32 user32)
endif()
add_test(NAME catch_tests COMMAND catch_tests)
