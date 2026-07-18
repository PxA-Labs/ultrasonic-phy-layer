# Fuzzing harnesses — requires clang + libFuzzer.
# Build with: cmake -DSW_BUILD_FUZZ=ON -DCMAKE_C_COMPILER=clang ..
# Each harness links against soundwave and libFuzzer.

function(sw_add_fuzz FUZZ_NAME)
    add_executable(${FUZZ_NAME} ${FUZZ_NAME}.c)
    target_link_libraries(${FUZZ_NAME} PRIVATE soundwave)
    target_compile_options(${FUZZ_NAME} PRIVATE -fsanitize=fuzzer)
    target_link_options(${FUZZ_NAME} PRIVATE -fsanitize=fuzzer)
endfunction()

sw_add_fuzz(fuzz_crc)
sw_add_fuzz(fuzz_css)
sw_add_fuzz(fuzz_ofdm)
sw_add_fuzz(fuzz_rs)
sw_add_fuzz(fuzz_api)
