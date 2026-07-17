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

$$Y_k = \frac{1}{\sqrt{N}} \sum_{n=0}^{N-1} y[n + N_{cp}] e^{-j \frac{2\pi k n}{N}}$$

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

The cross-correlation peak provides accurate timing estimation even in severe noise.

### 3.3 Carrier Frequency Offset (CFO) Estimation
A frequency offset $\Delta f_c$ introduces a phase rotation in the received samples:

$$y[n] = x[n] e^{j 2\pi \frac{\Delta f_c}{f_s} n}$$

Using Schmidl-Cox sync with two identical consecutive training symbols of period $N$, the CFO is estimated by checking the phase angle of the autocorrelation:

$$\Delta \hat{f}_c = \frac{f_s}{2\pi N} \angle \left( \sum_{n=0}^{N-1} y^*[n] y[n + N] \right)$$

---

## 4. Demodulation & Channel Equalization

### 4.1 Channel Estimation
Pilot subcarriers are embedded in the OFDM grid at predefined indices $K_p$. Let $X_p$ be the known pilot symbol transmitted. The Least Squares (LS) estimate of the channel at pilot subcarriers is:

$$\hat{H}_{LS}[k] = \frac{Y[k]}{X_p[k]}, \quad k \in K_p$$

For the remaining subcarriers, the channel frequency response is estimated using linear or cubic spline interpolation:

$$\hat{H}[k] = \text{Interpolate}\left(\hat{H}_{LS}[k_p]\right)$$

### 4.2 Equalization
To recover the transmitted data symbol $X_k$, we apply equalization to correct for the channel frequency response $\hat{H}[k]$:

- **Zero-Forcing (ZF) Equalizer** (simple, but amplifies noise in deep fades):
  $$\hat{X}_k = \frac{Y_k}{\hat{H}[k]}$$

- **Minimum Mean Square Error (MMSE) Equalizer** (balances noise enhancement and channel distortion):
  $$\hat{X}_k = \frac{Y_k \hat{H}^*[k]}{|\hat{H}[k]|^2 + \frac{\sigma_n^2}{\sigma_s^2}}$$

  where $\frac{\sigma_n^2}{\sigma_s^2}$ is the inverse Signal-to-Noise Ratio ($\text{SNR}^{-1}$).

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
