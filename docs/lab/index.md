# Signal Lab

An in-browser simulation of the two Soundwave waveforms, generated with the **same formulas as the C modulators** (`css_modulate.c`, `ofdm_modulate.c`). It runs entirely in your browser: no backend, no audio playback, no microphone. The noise is ideal white Gaussian noise. There is no room acoustics, speaker or microphone model, so nothing on this page predicts over-the-air performance.

<div class="sw-lab" id="sw-lab" markdown="0">

<p><label><input type="checkbox" id="sw-math"> Math view (show the equations behind each plot)</label></p>

<h2 id="lab-css">CSS: chirp frame</h2>

<div class="sw-lab-math">
<p>Each chirp carries SF bits. Symbol k (0 ≤ k &lt; M = 2<sup>SF</sup>) is the base up-chirp started k chips into its sweep: its frequency starts at f<sub>c</sub> − B/2 + kB/M, rises at B/T and wraps from f<sub>c</sub> + B/2 to f<sub>c</sub> − B/2. B = f<sub>s</sub>/D with D = round(f<sub>s</sub>/bandwidth) samples per chip, T = M/B. Bits are Gray mapped. A frame starts with 8 base up-chirps and 2 down-chirps. Raw rate = SF·B/M bit/s.</p>
</div>

<div class="sw-lab-controls">
<label>Sample rate
<select id="css-fs"><option value="44100" selected>44 100 Hz</option><option value="48000">48 000 Hz</option></select></label>
<label>Centre frequency f<sub>c</sub> <output id="css-f0-o"></output>
<input type="range" id="css-f0" min="15000" max="21000" step="250" value="19000"></label>
<label>Sweep bandwidth B <output id="css-bw-o"></output>
<input type="range" id="css-bw" min="1000" max="4000" step="250" value="2000"></label>
<label>Spreading factor SF
<select id="css-sf"><option>6</option><option>7</option><option selected>8</option><option>9</option><option>10</option></select></label>
<label>SNR (whole frame) <output id="css-snr-o"></output>
<input type="range" id="css-snr" min="-10" max="40" step="1" value="20"></label>
<label>Data bits (max 32)
<input type="text" id="css-bits" value="0100100001101001" maxlength="40"></label>
</div>

<canvas id="css-wave" width="900" height="180" aria-label="CSS waveform"></canvas>
<canvas id="css-spec" width="900" height="300" aria-label="CSS spectrogram"></canvas>
<p class="sw-lab-stats" id="css-stats"></p>
<p><button type="button" data-export="css-wave">Export waveform PNG</button> <button type="button" data-export="css-spec">Export spectrogram PNG</button></p>

<h2 id="lab-ofdm">OFDM: constellation and band occupancy</h2>

<div class="sw-lab-math">
<p>Active bins k = N/8+1 … N/2−1 of an N-point IFFT, with Hermitian symmetry so the output is real. Every 8th active bin is a pilot. Data bins carry BPSK (0 → −1, 1 → +1) or QPSK ((±1±j)/√2). x[n] = (1/√N)·Re Σ X<sub>k</sub> e<sup>j2πkn/N</sup>, followed by a cyclic prefix. The constellation adds complex AWGN at the chosen E<sub>s</sub>/N<sub>0</sub> directly on the subcarriers (a perfectly equalized flat channel). The theory curve is Q(√(2E<sub>b</sub>/N<sub>0</sub>)).</p>
</div>

<div class="sw-lab-controls">
<label>FFT size N
<select id="ofdm-n"><option>256</option><option>512</option><option>1024</option><option>2048</option></select></label>
<label>Cyclic prefix
<select id="ofdm-cp"><option>32</option><option selected>64</option><option>128</option></select></label>
<label>Mapping
<select id="ofdm-mod"><option value="qpsk" selected>QPSK</option><option value="bpsk">BPSK</option></select></label>
<label>E<sub>s</sub>/N<sub>0</sub> per subcarrier <output id="ofdm-snr-o"></output>
<input type="range" id="ofdm-snr" min="-5" max="30" step="1" value="12"></label>
</div>

<canvas id="ofdm-const" width="420" height="420" aria-label="OFDM constellation"></canvas>
<canvas id="ofdm-spec" width="900" height="300" aria-label="OFDM spectrogram"></canvas>
<p class="sw-lab-stats" id="ofdm-stats"></p>
<p><button type="button" data-export="ofdm-const">Export constellation PNG</button> <button type="button" data-export="ofdm-spec">Export spectrogram PNG</button></p>

</div>

<script src="signal-lab.js"></script>

## What this page does not do

- It does not model the acoustic channel (multipath, Doppler, speaker and microphone frequency response) or the receiver's synchronization, CFO correction and channel estimation. The constellation therefore shows the best case. Real received constellations are in the app's **Monitor** tab and come from `sw_ofdm_equalized_symbols`.
- The OFDM spectrogram shows why OFDM is **not** ultrasonic on the current code. Its energy spans about 5.5–22 kHz (see [Signal chain](../architecture/signal-chain.md)).
- The issue's suggested 16-QAM option is not offered, because the modem implements only BPSK and QPSK.
