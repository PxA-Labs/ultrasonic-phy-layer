# Fuzz regression corpus

Inputs that once crashed or hung a harness. Every `fuzz_*_smoke` CTest replays
the files under `regressions/<harness>/` before its random inputs, so a fixed
bug cannot silently return. When CI's `dsp-fuzz` job uploads a reproducer,
fix the bug, then add the file here with a descriptive name.

| File | Defect |
|---|---|
| `fuzz_ofdm/inv-snr-div-by-zero` | `ofdm_demodulate`: `1/10^(SNR/10)` divided by zero for silent pilots |
| `fuzz_api/css-sync-quadratic-timeout` | CSS sync used an O(len x N) direct correlation: 40 s for a 0.9 M-sample frame |
