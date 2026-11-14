# Soundwave: Physical Layer Mathematical Model

This document outlines the rigorous mathematical and physical formulations governing the physical layer (PHY) of the Soundwave communication system. Soundwave transmits digital data over short distances using ultrasonic acoustic waves (typically $18 \text{ kHz}$ to $22 \text{ kHz}$) using consumer-grade speakers and microphones.

---

## 1. Acoustic Wave Propagation & Channel Modeling

Acoustic transmission differs significantly from radio frequency (RF) propagation due to the slow speed of sound ($c \approx 343 \text{ m/s}$ at $20^\circ\text{C}$ in air) and high attenuation in the ultrasonic range.

### 1.1 The Acoustic Wave Equation
In a homogeneous, lossless fluid medium, acoustic pressure waves $p(\mathbf{r}, t)$ satisfy the three-dimensional wave equation:

$$\nabla^2 p(\mathbf{r}, t) - \frac{1}{c^2} \frac{\partial^2 p(\mathbf{r}, t)}{\partial t^2} = 0$$

where:
- $\nabla^2$ is the Laplacian operator.
- $\mathbf{r} = [x, y, z]^T$ represents the spatial coordinates.
- $c$ is the speed of sound.

### 1.2 Frequency-Dependent Attenuation (Path Loss)
Sound propagation in air experiences frequency-dependent attenuation due to classical viscosity, thermal conduction, and molecular relaxation of Nitrogen ($N_2$) and Oxygen ($O_2$). The attenuation coefficient $\alpha(f)$ in $\text{dB/m}$ can be approximated via Stokes' Law of sound attenuation at high frequencies:

$$\alpha(f) \approx \frac{8\pi^2 \eta}{3 \rho_0 c^3} f^2$$

where:
- $\eta$ is the dynamic viscosity of air.
- $\rho_0$ is the ambient density of air.
- $f$ is the carrier frequency.

The total path loss $A(d, f)$ over a distance $d$ (meters) for a signal with frequency $f$ is modeled as:

$$A(d, f) = d^{-\gamma} \cdot e^{-\alpha(f) d}$$

where $\gamma$ is the path loss exponent ($\gamma = 2$ for free-space spherical wave spreading, and $\gamma < 2$ in indoor waveguide-like corridors).

### 1.3 Multipath Channel Impulse Response (CIR)
Indoor acoustic channels are highly reverberant. The channel impulse response $h(t)$ is represented as a discrete tapped delay line:

$$h(t) = \sum_{i=0}^{L-1} a_i(t) \delta(t - \tau_i(t))$$

where:
- $L$ is the number of resolvable propagation paths.
- $a_i(t)$ is the time-varying path amplitude.
- $\tau_i(t)$ is the time-varying path delay.
- $\delta(t)$ is the Dirac delta function.

The corresponding frequency response (transfer function) is:

$$H(f, t) = \sum_{i=0}^{L-1} a_i(t) e^{-j 2\pi f \tau_i(t)}$$

### 1.4 Doppler Scaling Effect
Since the speed of sound $c$ is small, even slow relative motion between the transmitter and receiver creates significant Doppler shifts. The received signal $y(t)$ subject to a relative velocity $v$ is scaled in time:

$$y(t) = x\left( (1 + \beta) t - \tau_0 \right)$$

where:
- $\beta = \frac{v}{c}$ is the Doppler scaling factor.
- $\tau_0$ is the initial propagation delay.

The frequency shifts to:

$$f_{rx} = f_{tx} (1 + \beta)$$

---

## 2. Modulation Schemes

Soundwave supports two physical layer modulation options: Chirp Spread Spectrum (CSS) for high robustness, and Orthogonal Frequency Division Multiplexing (OFDM) for high throughput.

### 2.1 Chirp Spread Spectrum (CSS)
Chirp Spread Spectrum uses Linear Frequency Modulated (LFM) signals. It is highly robust to multipath fading and Doppler shifts.

#### 2.1.1 Continuous-Time Formulation
An LFM chirp symbol $s(t)$ defined over the duration $T$ is expressed as:

$$s(t) = A \cos \left( 2\pi \left( f_0 + \frac{B}{2T} t \right) t + \phi_0 \right), \quad 0 \leq t \leq T$$

where:
- $A$ is the signal amplitude.
- $f_0$ is the starting (carrier) frequency.
- $B$ is the bandwidth ($f_{end} - f_0$).
- $T$ is the chirp symbol duration.
- $\phi_0$ is the initial phase.

The instantaneous frequency $f_{inst}(t)$ varies linearly with time:

$$f_{inst}(t) = \frac{1}{2\pi} \frac{d}{dt} \left( 2\pi \left( f_0 + \frac{B}{2T} t \right) t + \phi_0 \right) = f_0 + \frac{B}{T} t$$

- If $B > 0$, the signal is an **up-chirp**.
- If $B < 0$, the signal is a **down-chirp**.

#### 2.1.2 Discrete-Time Formulation
Sampling at $f_s = 1/T_s$, the discrete-time chirp $s[n]$ is:

$$s[n] = A \cos \left( 2\pi \left( f_0 + \frac{B}{2N} n \right) n T_s + \phi_0 \right), \quad 0 \leq n \leq N-1$$

where $N = T / T_s$ is the number of samples per symbol.

### 2.2 Orthogonal Frequency Division Multiplexing (OFDM)
For high-rate communications, OFDM divides the transmission band into $N_c$ orthogonal subcarriers.

#### 2.2.1 Transmitted Signal Formulation
The baseband complex OFDM symbol $x(t)$ is formulated as:

$$x(t) = \sum_{k=0}^{N_c - 1} X_k e^{j 2\pi k \Delta f t}, \quad 0 \leq t \leq T_{sub}$$

where:
- $X_k$ is the complex modulation symbol (e.g., BPSK, QPSK, or QAM) mapped to the $k$-th subcarrier.
- $\Delta f = \frac{1}{T_{sub}}$ is the subcarrier spacing (ensuring orthogonality).
- $T_{sub}$ is the active symbol duration.

To eliminate Inter-Symbol Interference (ISI) caused by multipath delay spread, a Cyclic Prefix (CP) of duration $T_{cp} > \max(\tau_i)$ is prepended, yielding the full symbol duration $T_{sym} = T_{sub} + T_{cp}$:

$$x_{cp}(t) = \begin{cases} 
x(t + T_{sub} - T_{cp}), & 0 \leq t < T_{cp} \\
x(t - T_{cp}), & T_{cp} \leq t \leq T_{sym}
\end{cases}$$

#### 2.2.2 Discrete-Time Processing (IDFT/DFT)
Using a digital processor, modulation is performed using the Inverse Discrete Fourier Transform (IDFT):

$$x[n] = \frac{1}{\sqrt{N}} \sum_{k=0}^{N-1} X_k e^{j \frac{2\pi k n}{N}}, \quad 0 \leq n \leq N-1$$

And demodulation extracts the subcarriers via the Discrete Fourier Transform (DFT) at the receiver:

$$Y_k = \frac{1}{\sqrt{N}} \sum_{n=0}^{N-1} y[n + N_{cp} - b] e^{-j \frac{2\pi k n}{N}}, \quad b = \lfloor N_{cp} / 4 \rfloor$$

The FFT window starts $b$ samples inside the cyclic prefix rather than at its end (see section 4.0 for why).

#### 2.2.3 Ultrasonic Band Plan
The audio is real, so $X_{N-k} = X_k^*$ and only bins $1 \le k \le N/2 - 1$ are chosen freely. Bin $k$ sits at $f_k = k f_s / N$. The occupied band is set by `carrier_freq` $f_c$ and `bandwidth` $B$ (defaults 19 kHz and 2 kHz, i.e. 18–20 kHz):

$$K_a = \{k_{lo}, \dots, k_{hi}\}, \quad k_{lo} = \left\lceil \frac{(f_c - B/2) N}{f_s} \right\rceil + 1, \quad k_{hi} = \left\lfloor \frac{(f_c + B/2) N}{f_s} \right\rfloor - 1$$

The $+1$ / $-1$ leave one empty guard bin inside each band edge, so the main lobe of the outermost subcarrier stays (almost entirely) inside the band. Every bin outside $K_a$ (DC, the whole audible range, Nyquist) is zero on transmit, and the receiver uses only $K_a$ for timing, CFO, channel and noise estimation, equalization and demapping. A configuration is rejected unless $f_c - B/2 > 0$, $f_c + B/2 \le f_s/2 - f_s/N$ (one subcarrier spacing of guard below Nyquist) and $|K_a| \ge 4$. Every 8th active bin, starting with $k_{lo}$, is a pilot with value $+1, -1, +1, \dots$; the other $|K_a| - \lceil |K_a|/8 \rceil$ bins carry data, so one OFDM symbol carries $(|K_a| - \lceil |K_a|/8 \rceil) \cdot m$ bits with $m = 1$ (BPSK) or $2$ (QPSK). The code is `ofdm_layout_compute` (C) and `OfdmBand` (Dart), which use the same arithmetic.

**Transmit windowing.** A rectangular symbol has a sinc spectrum whose $1/f^2$ power sidelobes leave roughly $-26$ dB of the frame energy below 16 kHz even when every active bin is above 18 kHz. Each symbol therefore rises with a raised-cosine ramp $r[n] = \tfrac12\left(1 - \cos\frac{\pi (n + 1/2)}{W}\right)$ over its first $W = \lfloor N_{cp}/2 \rfloor$ samples, while the previous symbol continues with its cyclic suffix (its first $W$ body samples) weighted by $r[W-1-n]$. Because $r[n] + r[W-1-n] = 1$ the cross-fade has unit gain. It lies inside the cyclic prefix, before the receiver's FFT window (which starts at $N_{cp} - b \ge W$), so it costs no throughput; the frame only grows by the last symbol's fade-out:

$$\text{samples} = (2 + N_{sym}) (N + N_{cp}) + \lfloor N_{cp}/2 \rfloor$$

The two preamble copies are joined without a cross-fade so that they stay sample-identical (section 3). To keep that one junction continuous anyway, the preamble's ZC sequence is multiplied by the common phase $e^{j\varphi}$ for which $\text{Re}\{e^{j\varphi}(z[N - N_{cp}] - z[0])\} = 0$, with $z[n] = \sum_{k \in K_a} X_k e^{j 2\pi k n / N}$: the first sample of the second copy's prefix then equals the natural continuation of the first copy.

**Data whitening.** With only a few data bins (8 at $N = 256$ in the default band, i.e. 16 bits per QPSK symbol), repeated payload bytes would produce identical consecutive OFDM symbols, which a repetition detector cannot tell from the preamble. Data bits are therefore XORed with the PRBS15 sequence $x^{15} + x^{14} + 1$ (seed all ones, restarted every frame, `ofdm_scramble`) before mapping and after demapping.

`native/tests/test_ofdm_spectrum.c` computes the transmit spectrum of a typical frame and requires at least 98.5 % of the energy in $[f_c - B/2, f_c + B/2]$ and at most $-40$ dB below 16 kHz for every tested FFT size. The values it prints are listed in [Signal chain & parameters](architecture/signal-chain.md#ofdm-mode).

---

## 3. Synchronization & Frame Detection

Proper timing and frequency synchronization are critical in acoustic communication to align the receiver's decoding window and correct for carrier frequency offsets.

### 3.1 Preamble Detection via Matched Filtering
For Chirp-based systems, frame detection is achieved by correlating the received signal $y[n]$ with the template chirp $s[n]$:

$$R_{ys}[m] = \sum_{n=0}^{N-1} y[n + m] s^*[n]$$

A threshold detector identifies the start of the frame at sample $m_{start}$:

$$m_{start} = \arg\max_{m} \left| R_{ys}[m] \right|^2 \quad \text{subject to } \left| R_{ys}[m_{start}] \right|^2 > \theta \cdot \sigma_n^2$$

where $\theta$ is a scaling threshold and $\sigma_n^2$ is the estimated noise variance.

### 3.2 Zadoff-Chu Sequences for OFDM Sync
For OFDM, a Zadoff-Chu (ZC) sequence is placed in the preamble. ZC sequences possess constant amplitude and zero autocorrelation properties. The $u$-th root ZC sequence of length $N_{ZC}$ (where $N_{ZC}$ is prime) is defined as:

$$x_u[n] = e^{-j \frac{\pi u n(n+1)}{N_{ZC}}}, \quad 0 \leq n < N_{ZC}$$

The preamble uses root $u = 1$ with $N_{ZC} = |K_a|$ on the active bins (section 2.2.3), sent twice. Coarse timing is the Schmidl-Cox repetition metric over the period $L = N + N_{cp}$, computed on the analytic signal. With a narrow band that peak is broad, so it is refined from the preamble itself. A window that starts $s$ samples away from the symbol body gives $Y_k = H_k X_k e^{j 2\pi k s / N}$, so with $D_k = (Y_{k+1} X_{k+1}^*)(Y_k X_k^*)^*$ summed over adjacent active bins of both copies,

$$\hat{s} = \frac{N}{2\pi} \angle \sum_k D_k, \qquad \hat{\delta} = \hat{s} + b$$

and the frame start is moved by $-\operatorname{round}(\hat{\delta})$ (two passes, `ofdm_refine_timing`). The same sums give a preamble score $|\sum_k D_k| / \sum_k |D_k|$: close to 1 for the real preamble, about $1/\sqrt{|K_a|}$ for anything else. A Schmidl-Cox candidate that scores below 0.5 (some other repetition) is re-checked with a matched filter on the known two-copy preamble, and the better-scoring start is used (`ofdm_locate_preamble`).

### 3.3 Carrier Frequency Offset (CFO) Estimation
A frequency offset $\Delta f_c$ introduces a phase rotation in the received samples:

$$y[n] = x[n] e^{j 2\pi \frac{\Delta f_c}{f_s} n}$$

Using Schmidl-Cox sync with two identical consecutive training symbols of period $N$, the CFO is estimated by checking the phase angle of the autocorrelation:

$$\Delta \hat{f}_c = \frac{f_s}{2\pi N} \angle \left( \sum_{n=0}^{N-1} y^*[n] y[n + N] \right)$$

In the OFDM receiver the two training symbols are the two identical preamble symbols, each with its cyclic prefix, so the repetition period is $L = N + N_{cp}$. The receiver evaluates the correlation in the frequency domain, on the same FFT windows that the channel estimate uses (section 4.0):

$$\Delta \hat{f}_c = \frac{f_s}{2\pi L} \angle \left( \sum_{k \in K_a} Y_1^*[k] \, Y_2[k] \right)$$

A frequency offset rotates each active subcarrier of the second copy by $e^{j 2\pi \Delta f_c L / f_s}$ relative to the first. Both windows lie inside the repeated preamble for every timing error the receiver tolerates, so a noiseless frame gives exactly $\Delta \hat{f}_c = 0$. The time-domain sum over a full window of $L$ samples does not have this property. With a timing error of $\delta$ samples, $|\delta|$ samples of that window fall outside the repetition and bias the estimate. Because the signal is real, its mirror-image spectrum leaks into the active band, and the leakage grows with the offset. The estimate is therefore run twice: the second pass estimates the small residual left after correcting with the first estimate, and the two are added.

The received audio is real, so the timing metric and the CFO correction run on its analytic signal $z[n]$. It is formed over a buffer of length $M$ with the DFT:

$$Z[k] = \begin{cases} X[k], & k = 0 \text{ or } k = M/2 \ (M \text{ even}) \\ 2X[k], & 0 < k < M/2 \\ 0, & M/2 < k < M \end{cases}$$

so that $\text{Re}\{z[n]\} = x[n]$ exactly, and the CFO-corrected real signal is $\text{Re}\{z[n] e^{-j 2\pi \Delta\hat{f}_c n / f_s}\}$. Both the real and imaginary parts of each positive-frequency bin must be doubled. Doubling only the real part gives $Z[k] = 2\,\text{Re}\,X[k] + j\,\text{Im}\,X[k]$, whose real part is $\tfrac{3}{4}x[n] + \tfrac{1}{4}x[(-n) \bmod M]$. That adds a 25 % time-reversed copy of the whole buffer to the signal, which held the noiseless OFDM loopback EVM at about 28 to 45 %.

---

## 4. Demodulation & Channel Equalization

### 4.0 Receiver Timing and FFT Window Placement
Let the detected frame start be off by $\delta$ samples, so that each symbol's FFT window starts at $N_{cp} - b + \delta$ into the symbol. While $-(N_{cp} - b) \le \delta \le b$, the window stays inside the current symbol plus its own cyclic prefix. It is then a cyclic shift of the transmitted block (ignoring multipath for this argument):

$$Y_k = H_k X_k \, e^{-j \frac{2\pi k (b - \delta)}{N}}$$

The ramp is the same for the preamble and every data symbol, so it is part of the channel estimate $\hat{H}[k]$ and is removed exactly by equalization. The first $W = \lfloor N_{cp}/2 \rfloor$ samples of each symbol hold the transmit cross-fade (section 2.2.3), so the ISI-free range is $-(N_{cp} - b - W) \le \delta \le b$, i.e. $\pm N_{cp}/4$ with these defaults; fine timing (section 3.2) keeps $\delta$ near 0. A data symbol is demodulated when its whole FFT window lies inside the received buffer, so a buffer that ends at the frame's last sample yields every symbol. If $\delta > b$ (the window is late), it takes $\delta - b$ samples from the next symbol's cyclic prefix. That causes ISI and inter-carrier interference that no equalizer can remove: in a noiseless loopback, a window just one sample late already gives about 20 % EVM. The Schmidl-Cox timing peak of section 3 can land one or two samples off, so the receiver samples $b = \lfloor N_{cp}/4 \rfloor$ samples early. The cost is that the multipath delay spread the CP can absorb drops from $N_{cp}$ to $N_{cp} - b$.

### 4.1 Channel Estimation
The channel is estimated from the two identical Zadoff-Chu preamble symbols (section 3.2), which occupy every active subcarrier $k \in K_a$. Let $Y_1[k]$ and $Y_2[k]$ be their DFTs and $X_{ZC}[k]$ the known preamble values. The Least Squares (LS) estimate averages the two copies:

$$\hat{H}_{LS}[k] = \frac{Y_1[k] + Y_2[k]}{2 X_{ZC}[k]}, \quad k \in K_a$$

Data subcarriers lie inside $K_a$, so they need no interpolation. Linear interpolation (`chanest_linear_interp`) only extends $\hat{H}$ to the guard and null bins:

$$\hat{H}[k] = \text{Interpolate}\left(\hat{H}_{LS}[k_a]\right)$$

The two copies differ only by noise, $Y_1 - Y_2 = W_1 - W_2$, which gives the per-subcarrier noise variance:

$$\hat{\sigma}_n^2 = \frac{1}{2|K_a|} \sum_{k \in K_a} \left| Y_1[k] - Y_2[k] \right|^2$$

### 4.2 Equalization
To recover the transmitted data symbol $X_k$, we apply equalization to correct for the channel frequency response $\hat{H}[k]$:

- **Zero-Forcing (ZF) Equalizer** (simple, but amplifies noise in deep fades):
  $$\hat{X}_k = \frac{Y_k}{\hat{H}[k]}$$

- **Minimum Mean Square Error (MMSE) Equalizer** (balances noise enhancement and channel distortion):
  $$\hat{X}_k = \frac{Y_k \hat{H}^*[k]}{|\hat{H}[k]|^2 + \frac{\sigma_n^2}{\sigma_s^2}}$$

  where $\frac{\sigma_n^2}{\sigma_s^2}$ is the inverse Signal-to-Noise Ratio ($\text{SNR}^{-1}$). The BPSK and QPSK data symbols have unit energy ($\sigma_s^2 = 1$), so the receiver uses $\hat{\sigma}_n^2$ from section 4.1, clamped to $[0, 10]$. In a noiseless channel MMSE therefore reduces to ZF.

**Common phase tracking.** The channel estimate comes from the preamble only. A residual CFO error $\epsilon$ rotates data symbol $m$ by about $2\pi \epsilon (m + 2) L / f_s$, and with about 10 active bins the CFO estimate is not precise enough to hold the phase over a long frame. Before equalization each data symbol is therefore derotated by the angle of its pilots against the channel estimate:

$$\theta_m = \angle \sum_{p} Y_m[k_p] \left(\hat{H}[k_p] X_p\right)^*$$

---

## 5. Channel Coding & Error Control

Acoustic environments are prone to burst noise (e.g. key clicks, claps). We apply Forward Error Correction (FEC) to guarantee error-free recovery.

### 5.1 Reed-Solomon Code
A Reed-Solomon code $RS(n, k)$ over the Galois Field $GF(2^m)$ converts $k$ data symbols into an $n$-symbol codeword.

- **Block Length**: $n = 2^m - 1$ symbols.
- **Message Size**: $k$ symbols.
- **Parity Bytes**: $2t = n - k$ symbols.
- **Error Correction Capability**: The code can correct up to $t$ symbol errors:
  $$t = \lfloor \frac{n - k}{2} \rfloor$$

The generator polynomial $g(x)$ for the code is given by:

$$g(x) = \prod_{i=0}^{2t-1} \left( x - \alpha^{i + i_0} \right)$$

where $\alpha$ is a primitive element of $GF(2^m)$ and $i_0$ is an integer offset (typically $i_0 = 1$).

### 5.2 Error Detection (CRC-32)
Before encoding with RS, the payload is appended with a Cyclic Redundancy Check (CRC-32) checksum to verify frame integrity post-decoding. The CRC-32 generator polynomial is:

$$G(x) = x^{32} + x^{26} + x^{23} + x^{22} + x^{16} + x^{12} + x^{11} + x^{10} + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1$$

---

## 6. Automatic Gain Control (AGC)

Microphone sensitivity, speaker volume and distance change the received level by tens of dB. The RX pipeline normalizes the level before frame detection (`native/src/agc/agc.c`, issue #92). For each input sample $x[n]$:

### 6.1 Power Estimate
A one-pole average of $x^2$ approximates a 10 ms RMS window:

$$p[n] = p[n-1] + \alpha_{rms}\left(x[n]^2 - p[n-1]\right)$$

### 6.2 Desired and Smoothed Gain

$$g_d[n] = \operatorname{clamp}\!\left(\frac{A_{target}}{\sqrt{p[n] + \epsilon}},\; g_{min},\; g_{max}\right)$$

$$g[n] = g[n-1] + \alpha\left(g_d[n] - g[n-1]\right), \qquad \alpha = \begin{cases} \alpha_{att} & g_d[n] < g[n-1] \text{ (attack)} \\ \alpha_{rel} & \text{otherwise (release)} \end{cases}$$

Each one-pole coefficient follows from its time constant $\tau$:

$$\alpha_k = 1 - e^{-1/(\tau_k f_s)}$$

### 6.3 Peak Guard and Output
A frame arriving after silence would otherwise be multiplied by the silence gain for the first milliseconds. The gain is therefore capped instantly on peaks:

$$g[n] \leftarrow \min\!\left(g[n],\; \frac{L_{peak}}{|x[n]|}\right), \qquad y[n] = g[n]\, x[n], \quad |y[n]| \le L_{peak}$$

Non-finite samples produce $y[n] = 0$ and leave $p$ and $g$ unchanged.

### 6.4 Parameters

| Symbol | Value | Meaning |
|---|---|---|
| $A_{target}$ | 0.25 (−12 dBFS) | Output RMS target |
| $\tau_{rms}$ | 10 ms | Power-estimate window |
| $\tau_{att}$ / $\tau_{rel}$ | 1 ms / 100 ms | Gain attack / release |
| $[g_{min}, g_{max}]$ | [0.1, 40] = [−20, +32] dB | Gain range |
| $L_{peak}$ | 1.0 | Output peak limit (full scale) |

The reported gain is $G_{dB} = 20\log_{10} g$. Measured (`test_agc`): chirps 30 dB below to 10 dB above target settle within ±0.11 dB; convergence takes 10 ms after silence; cost is about 0.01 ms per 10 ms chunk.
