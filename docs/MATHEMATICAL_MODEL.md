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

Soundwave supports two physical layer modulation options: Chirp Spread Spectrum (CSS) for robustness at low rates, and Orthogonal Frequency Division Multiplexing (OFDM) for high throughput.

### 2.1 Chirp Spread Spectrum (CSS)
CSS in Soundwave uses LoRa-style chirp symbols: every data symbol is the same linear up-chirp, cyclically shifted in frequency, so one chirp carries $SF$ bits. Implementation: `native/src/css/css_modulate.c` (transmitter) and `native/src/css/css_demodulate.c` (receiver).

#### 2.1.1 Parameters and sampling
| Symbol | Meaning | Config field / default |
|---|---|---|
| $f_s$ | sample rate | `sample_rate`, 44 100 Hz |
| $f_c$ | band centre | `carrier_freq`, 19 000 Hz |
| $SF$ | spreading factor, $6 \le SF \le 10$ | `sf`, 8 |
| $M = 2^{SF}$ | chips per symbol (and symbol alphabet size) | |
| $D = \operatorname{round}(f_s / B_{cfg})$ | samples per chip, $D \ge 1$ | from `bandwidth` (2000 Hz) |
| $B = f_s / D$ | effective sweep bandwidth | |
| $N = M D$ | samples per symbol | |
| $T = M / B = N / f_s$ | symbol duration | |

The configured bandwidth is quantised to $f_s / D$ so that a chip is a whole number of samples and every symbol is exactly $N = MD$ samples. At 44.1 kHz, `bandwidth` 2000 gives $D = 22$, $B = 2004.5$ Hz; 4000 gives $D = 11$, $B = 4009.1$ Hz. The receiver works at the chip rate $B$ after filtering, so $D$ is the oversampling factor of the audio stream. `symbol_duration` is **not used** by CSS: the symbol length follows from $SF$ and $B$. The band $[f_c - B/2, f_c + B/2]$ must lie in $(0, f_s/2]$; otherwise the configuration is rejected (`SW_ERR_BAD_PARAM`).

#### 2.1.2 Symbol waveform
Symbol value $k \in \{0, \dots, M-1\}$ is the base up-chirp started $k$ chips into its sweep. Its instantaneous frequency is

$$f_k(t) = f_c - \frac{B}{2} + B \left( \frac{k}{M} + \frac{t}{T} \bmod 1 \right), \qquad 0 \le t < T,$$

that is, it starts at $f_c - B/2 + kB/M$, rises at $B/T$ Hz/s and wraps from $f_c + B/2$ back to $f_c - B/2$ at $t_w = T(1 - k/M)$, which is sample $(M - k) D$. The transmitted sample is $s[n] = A \cos(2\pi \varphi(n / f_s))$ with $\varphi$ the integral of $f_k$; phase is carried across symbols so the signal is continuous. The down-chirp used in the preamble sweeps $f_c + B/2 \to f_c - B/2$.

#### 2.1.3 Bits to symbols (Gray mapping) and frame
Bits are taken MSB first, $SF$ at a time (the last group is zero padded). A group with value $v$ is sent as the symbol $k$ whose Gray code equals $v$, i.e. $v = k \oplus (k \gg 1)$. The most likely demodulation error is a neighbouring bin ($k \pm 1$, also across the wrap $M-1 \leftrightarrow 0$), and neighbours differ in exactly one bit. A frame is

$$\underbrace{8 \times \text{base up-chirp } (k = 0)}_{\text{preamble}} \;\; \underbrace{2 \times \text{down-chirp}}_{\text{sync word}} \;\; \underbrace{\lceil n_{bits} / SF \rceil \times \text{data up-chirps}}_{\text{payload}}$$

so it occupies $(10 + \lceil n_{bits}/SF \rceil) \cdot N$ samples. Data symbols are always up-chirps; a payload can therefore contain base up-chirps (e.g. zero bytes) but never a down-chirp.

#### 2.1.4 Demodulation (dechirp + FFT)
1. **Complex baseband.** $z[n] = \text{LPF}\{ y[n] e^{-j 2\pi f_c n / f_s} \}$ with a Hamming-windowed sinc low-pass of $10D + 1$ taps and cut-off $0.6B$. It removes the negative-frequency image at $-2f_c$ and the noise outside the band; its group delay is compensated so $z$ is aligned with $y$.
2. **Chip samples.** For data symbol $i$ starting at $t_i = \hat{t}_0 + (10 + i) N$ (fractional), take $z$ at $t_i + mD$, $m = 0, \dots, M-1$ (linear interpolation), and remove the estimated frequency offset: $v[m] = z(t_i + mD)\, e^{-j 2\pi \widehat{\Delta f} (t_i + mD)/f_s}$.
3. **Dechirp.** Multiply by the conjugate chip-rate base chirp $c[m] = e^{j\pi(m^2/M - m)}$. Symbol $k$ becomes a tone of $k/M$ cycles per chip; at the chip rate the wrapped part of the chirp aliases onto the same tone.
4. **FFT and decision.** $\hat{k} = \arg\max_k |\mathrm{FFT}_M\{v[m] c^*[m]\}[k]|^2$, then $v = \hat{k} \oplus (\hat{k} \gg 1)$ gives the $SF$ bits.

The decision is a bank of $M$ matched filters computed by one $M$-point FFT. Integrating $M$ chips gives a processing gain of $10 \log_{10} M$ dB (18.1 dB at SF6, 30.1 dB at SF10).

#### 2.1.5 Valid SF range (computed, 44.1 kHz)
| $SF$ | $N$ at 2 kHz ($D$=22) | $T$ at 2 kHz | Raw rate at 2 kHz | $N$ at 4 kHz ($D$=11) | $T$ at 4 kHz | Raw rate at 4 kHz | Bin spacing $B/M$ at 4 kHz |
|---|---|---|---|---|---|---|---|
| 6 | 1408 | 31.9 ms | 187.9 bit/s | 704 | 16.0 ms | 375.9 bit/s | 62.6 Hz |
| 7 | 2816 | 63.9 ms | 109.6 bit/s | 1408 | 31.9 ms | 219.2 bit/s | 31.3 Hz |
| 8 (default) | 5632 | 127.7 ms | 62.6 bit/s | 2816 | 63.9 ms | 125.3 bit/s | 15.7 Hz |
| 9 | 11264 | 255.4 ms | 35.2 bit/s | 5632 | 127.7 ms | 70.5 bit/s | 7.8 Hz |
| 10 | 22528 | 510.8 ms | 19.6 bit/s | 11264 | 255.4 ms | 39.2 bit/s | 3.9 Hz |

Raw rate $= SF \cdot B / M$ (computed from the formulas above, not measured; preamble and FEC excluded). At 2 kHz the bin spacing is half the 4 kHz value.

Why $6 \le SF \le 10$:

- **Upper bound.** A frequency error of half a bin moves the FFT peak to the wrong symbol. The preamble estimate below removes a static offset, but what changes during a frame is not tracked: a speaker/microphone clock mismatch of ±50 ppm per device is up to 2 Hz at 20 kHz, and 0.1 m/s of hand movement is a 5.5 Hz Doppler shift at 19 kHz. At SF10 the bin is already 3.9 Hz (4 kHz band) or 2.0 Hz (2 kHz band); SF11/12 would be 1–2 Hz (0.5–1 Hz at 2 kHz) with 0.5–2 s symbols. Symbols are also capped at 1 s (`CSS_MAX_SYMBOL_SEC`), which SF11 already exceeds at 2 kHz.
- **Lower bound.** Below SF6 the processing gain is under 18 dB and the preamble correlation of noise or data ($\approx 1/M$, see 3.1) gets close to the detection threshold.
- **Oversampling.** For any $B \le f_s/2$, $D = \operatorname{round}(f_s/B) \ge 2$ samples per chip. The symbol is an integer number of samples for every SF, so no fractional resampling is needed.

#### 2.1.6 FEC
CSS and OFDM share the frame FEC: Reed-Solomon RS(255,223) with 32 parity bytes (corrects 16 byte errors), on or off. There is no adjustable code rate; the former `coding_rate` setting had no effect and was removed from the app. The `sw_config_t.coding_rate` field remains for ABI compatibility and is ignored.

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

---

## 3. Synchronization & Frame Detection

Proper timing and frequency synchronization are critical in acoustic communication to align the receiver's decoding window and correct for carrier frequency offsets.

### 3.1 CSS Preamble Detection
The CSS receiver (`css_detect_frame()` in `native/src/css/css_demodulate.c`; `sync_detect_frame()` mode 0 and `sw_detect_frame()` call it) searches the **whole** buffer on the complex baseband $z[n]$ of section 2.1.4. For every lag $m$ it computes the normalised correlation of the $N$-sample window with the base up-chirp $u[n]$ and with the down-chirp $u^*[n]$:

$$\rho_{up}[m] = \frac{\left| \sum_{n=0}^{N-1} z[m+n] u^*[n] \right|^2}{\sum_n |z[m+n]|^2 \cdot N}, \qquad \rho_{dn}[m] \text{ likewise with } u[n],$$

so $0 \le \rho \le 1$ regardless of signal level (FFT overlap-save correlation, $O(L \log N)$). Windows more than 60 dB below the loudest window are ignored. A preamble starting at $m$ scores

$$U(m) = \frac{1}{8} \sum_{i=0}^{7} \rho_{up}[m + iN], \qquad D(m) = \frac{1}{2} \sum_{i=8}^{9} \rho_{dn}[m + iN].$$

Only lags with the whole 10-chirp preamble inside the buffer are scored, so a preamble near the end of the buffer is not judged on part of its chirps.

- **Threshold.** In noise, $\rho \approx 1/(1.2M)$ (the low-pass passes about $1.2M$ complex degrees of freedom per window). Detection needs $U \ge \gamma$ and $\max_{|\delta| \le 2D} D(m+\delta) \ge \gamma$ with $\gamma = \min(0.5, 4\theta/M)$ and $\theta$ = `threshold` (default 3), i.e. 12/M: 0.19 at SF6, 0.012 at SF10. With $\rho \approx \text{SNR}_{band}/(1+\text{SNR}_{band})$ this corresponds to an in-band SNR of about −6 dB (SF6) to −19 dB (SF10).
- **Why data cannot fake it.** Data symbols are up-chirps only. A shifted up-chirp correlated with the down-chirp template gives $\rho \approx 1/(2M)$ (stationary-phase estimate), the same order as noise, so the two-down-chirp term stays below $\gamma$ inside any payload, including payloads of zero bytes (runs of base up-chirps). The old waveform sent a down-chirp for every 1 bit, so the old 8-up/2-down preamble could occur inside data.
- **Peak selection.** The first lag that passes is at most one symbol early (7 of 8 up slots and 1 of 2 down slots still match), so the start is the maximum of $U + D$ within one symbol after it. A later, stronger frame in the same buffer is not preferred over the first one.
- **Fractional timing and offset.** A frequency offset $\Delta f$ delays the up-chirp correlation peak and advances the down-chirp peak by $\Delta f / (B/T)$ seconds, i.e. one chip per bin. With $t_{up}$, $t_{dn}$ the parabola-refined peaks of $U$ and $D$ within $\pm 2D$ samples,

$$\hat{t}_0 = \frac{t_{up} + t_{dn}}{2}, \qquad \widehat{\Delta f} = \frac{t_{dn} - t_{up}}{2} \cdot \frac{B}{N} \text{ Hz}.$$

The data symbols are demodulated at the fractional start $\hat{t}_0$ with $\widehat{\Delta f}$ removed (offsets up to about ±2 bins). `sw_detect_frame` reports $\operatorname{round}(\hat{t}_0)$ and the in-band SNR estimate $10\log_{10}(\bar\rho / (1 - \bar\rho))$, where $\bar\rho$ is the preamble mean.

### 3.2 Zadoff-Chu Sequences for OFDM Sync
For OFDM, a Zadoff-Chu (ZC) sequence is placed in the preamble. ZC sequences possess constant amplitude and zero autocorrelation properties. The $u$-th root ZC sequence of length $N_{ZC}$ (where $N_{ZC}$ is prime) is defined as:

$$x_u[n] = e^{-j \frac{\pi u n(n+1)}{N_{ZC}}}, \quad 0 \leq n < N_{ZC}$$

The cross-correlation peak provides accurate timing estimation even in severe noise.

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

The ramp is the same for the preamble and every data symbol, so it is part of the channel estimate $\hat{H}[k]$ and is removed exactly by equalization. If $\delta > b$ (the window is late), it takes $\delta - b$ samples from the next symbol's cyclic prefix. That causes ISI and inter-carrier interference that no equalizer can remove: in a noiseless loopback, a window just one sample late already gives about 20 % EVM. The Schmidl-Cox timing peak of section 3 can land one or two samples off, so the receiver samples $b = \lfloor N_{cp}/4 \rfloor$ samples early. The cost is that the multipath delay spread the CP can absorb drops from $N_{cp}$ to $N_{cp} - b$.

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
