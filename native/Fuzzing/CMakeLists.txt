# Fuzz harnesses (issue #28).
#
# Every harness exposes LLVMFuzzerTestOneInput() and is built in one of two modes:
#
#   SW_ENABLE_FUZZER=ON  -> real libFuzzer binaries (LLVM Clang only):
#       cmake -B build-fuzz -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
#             -DSW_ENABLE_FUZZER=ON -DSW_ENABLE_ASAN=ON -DSW_ENABLE_UBSAN=ON
#       ./build-fuzz/Fuzzing/fuzz_api -max_total_time=60
#
#   otherwise (SW_FUZZ_SMOKE=ON, default) -> harness + standalone_main.c driver,
#       registered with CTest as <name>_smoke. Each run replays the committed
#       reproducers in regressions/<name>/ (inputs that once crashed or hung),
#       then feeds SW_FUZZ_SMOKE_RUNS deterministic pseudo-random inputs. Combine with SW_ENABLE_ASAN/UBSAN for sanitizer coverage on any
#       compiler (GCC, AppleClang, MSVC).

set(SW_FUZZ_TARGETS
    fuzz_crc
    fuzz_rs
    fuzz_css
    fuzz_ofdm
    fuzz_packet
    fuzz_fec
    fuzz_api
)

# On macOS, Guard Malloc places every allocation against a guard page, so heap
# overruns fault even when ASan is unavailable (e.g. AppleClang on new macOS).
set(SW_GUARD_MALLOC_DYLIB "/usr/lib/libgmalloc.dylib")
if(APPLE AND NOT SW_ENABLE_ASAN AND EXISTS "${SW_GUARD_MALLOC_DYLIB}")
    set(SW_FUZZ_USE_GUARD_MALLOC ON)
else()
    set(SW_FUZZ_USE_GUARD_MALLOC OFF)
endif()

foreach(target ${SW_FUZZ_TARGETS})
    if(SW_ENABLE_FUZZER)
        add_executable(${target} ${target}.c)
        target_compile_options(${target} PRIVATE -fsanitize=fuzzer)
        target_link_options(${target} PRIVATE -fsanitize=fuzzer)
    else()
        add_executable(${target} ${target}.c standalone_main.c)
        # Replay every committed reproducer (regressions/<target>/*) first.
        file(GLOB _regressions "${CMAKE_CURRENT_SOURCE_DIR}/regressions/${target}/*")
        add_test(NAME ${target}_smoke
                 COMMAND ${target} -runs=${SW_FUZZ_SMOKE_RUNS} -seed=1 ${_regressions})
        set_tests_properties(${target}_smoke PROPERTIES LABELS "fuzz" TIMEOUT 600)
        if(SW_FUZZ_USE_GUARD_MALLOC)
            set_tests_properties(${target}_smoke PROPERTIES
                ENVIRONMENT "DYLD_INSERT_LIBRARIES=${SW_GUARD_MALLOC_DYLIB};MallocScribble=1")
        endif()
    endif()
    target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(${target} PRIVATE soundwave kiss_fft miniaudio)
    if(WIN32)
        target_link_libraries(${target} PRIVATE ole32 user32)
    else()
        target_link_libraries(${target} PRIVATE m)
    endif()
endforeach()
