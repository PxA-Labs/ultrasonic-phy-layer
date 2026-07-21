# Benchmark CMake — builds standalone benchmark executables that output JSON.

function(sw_add_benchmark BENCH_NAME BENCH_SOURCE)
    add_executable(${BENCH_NAME} ${BENCH_SOURCE})
    target_link_libraries(${BENCH_NAME} PRIVATE soundwave kissfft)
    if(NOT WIN32)
        target_link_libraries(${BENCH_NAME} PRIVATE m)
    endif()
endfunction()

sw_add_benchmark(bench_crc   benchmark_crc.c)
sw_add_benchmark(bench_fft   benchmark_fft.c)
sw_add_benchmark(bench_ofdm  benchmark_ofdm.c)
sw_add_benchmark(bench_css   benchmark_css.c)
sw_add_benchmark(bench_rs    benchmark_rs.c)
