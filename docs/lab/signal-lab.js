// Soundwave Signal Lab: client-side simulation of the CSS and OFDM waveforms
// exactly as native/src/css/css_modulate.c and native/src/ofdm/ofdm_modulate.c
// generate them. Idealised (no channel model beyond AWGN); not measurements.
(function () {
  "use strict";

  // ---------- utilities ----------
  function $(id) { return document.getElementById(id); }
  function css(name, fallback) {
    var v = getComputedStyle(document.body).getPropertyValue(name).trim();
    return v || fallback;
  }
  // Mulberry32 PRNG so plots are reproducible for a given seed.
  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function gauss(r) {
    var u = Math.max(r(), 1e-12), v = r();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }
  // In-place radix-2 FFT on separate re/im arrays (length power of two).
  function fft(re, im) {
    var n = re.length, i, j, k, len;
    for (i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        var t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    for (len = 2; len <= n; len <<= 1) {
      var ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
      for (i = 0; i < n; i += len) {
        var cr = 1, ci = 0;
        for (k = 0; k < len / 2; k++) {
          var ar = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
          var ai = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
          re[i + k + len / 2] = re[i + k] - ar; im[i + k + len / 2] = im[i + k] - ai;
          re[i + k] += ar; im[i + k] += ai;
          var ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr;
        }
      }
    }
  }
  function addNoise(x, snrDb, r) {
    var p = 0, i;
    for (i = 0; i < x.length; i++) p += x[i] * x[i];
    p /= x.length;
    var sd = Math.sqrt(p / Math.pow(10, snrDb / 10));
    var y = new Float64Array(x.length);
    for (i = 0; i < x.length; i++) y[i] = x[i] + sd * gauss(r);
    return y;
  }
  function erfc(x) { // Numerical Recipes erfcc, |error| < 1.2e-7
    var z = Math.abs(x), t = 1 / (1 + 0.5 * z);
    var r = t * Math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 +
      t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 +
      t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
    return x >= 0 ? r : 2 - r;
  }
  function qfunc(x) { return 0.5 * erfc(x / Math.SQRT2); }

  // ---------- drawing ----------
  function ctxOf(c) {
    var g = c.getContext("2d");
    g.fillStyle = css("--md-default-bg-color", "#fff");
    g.fillRect(0, 0, c.width, c.height);
    return g;
  }
  function axes(g, c, title, xlab, ylab) {
    g.fillStyle = css("--md-default-fg-color", "#000");
    g.font = "12px sans-serif";
    g.fillText(title, 8, 14);
    g.fillStyle = css("--md-default-fg-color--light", "#666");
    g.fillText(xlab, c.width - g.measureText(xlab).width - 6, c.height - 6);
    g.fillText(ylab, 8, 28);
  }
  function linePlot(c, ys, title, xlab, ylab) {
    var g = ctxOf(c), w = c.width, h = c.height, m = 34;
    var mx = 1e-9, i;
    for (i = 0; i < ys.length; i++) mx = Math.max(mx, Math.abs(ys[i]));
    g.strokeStyle = css("--md-default-fg-color--lightest", "#ccc");
    g.beginPath(); g.moveTo(m, h / 2); g.lineTo(w - 6, h / 2); g.stroke();
    g.strokeStyle = css("--md-primary-fg-color", "#3f51b5");
    g.lineWidth = 1;
    g.beginPath();
    for (i = 0; i < ys.length; i++) {
      var x = m + (w - m - 6) * i / (ys.length - 1);
      var y = h / 2 - (h / 2 - m / 2) * ys[i] / mx;
      if (i) g.lineTo(x, y); else g.moveTo(x, y);
    }
    g.stroke();
    axes(g, c, title, xlab, ylab);
  }
  // Spectrogram: Hann-windowed STFT, dB, perceptually ordered grey-to-accent map.
  function spectrogram(c, x, fs, nfft, fmax, title) {
    var g = ctxOf(c), w = c.width, h = c.height, top = 20, left = 34;
    var hop = Math.max(1, Math.floor((x.length - nfft) / (w - left)));
    var cols = Math.floor((x.length - nfft) / hop) + 1;
    var bins = Math.min(nfft / 2, Math.floor(fmax / fs * nfft));
    var win = new Float64Array(nfft), i, k;
    for (i = 0; i < nfft; i++) win[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (nfft - 1));
    var img = g.createImageData(cols, bins), mags = [], peak = -300;
    for (var col = 0; col < cols; col++) {
      var re = new Float64Array(nfft), im = new Float64Array(nfft);
      for (i = 0; i < nfft; i++) re[i] = x[col * hop + i] * win[i];
      fft(re, im);
      var colm = new Float64Array(bins);
      for (k = 0; k < bins; k++) {
        colm[k] = 10 * Math.log10(re[k] * re[k] + im[k] * im[k] + 1e-20);
        peak = Math.max(peak, colm[k]);
      }
      mags.push(colm);
    }
    for (col = 0; col < cols; col++) {
      for (k = 0; k < bins; k++) {
        var v = Math.max(0, Math.min(1, (mags[col][k] - peak + 60) / 60));
        var p = ((bins - 1 - k) * cols + col) * 4;
        img.data[p] = Math.round(20 + 235 * Math.pow(v, 1.5));
        img.data[p + 1] = Math.round(20 + 180 * v);
        img.data[p + 2] = Math.round(60 + 120 * (1 - v));
        img.data[p + 3] = 255;
      }
    }
    var tmp = document.createElement("canvas");
    tmp.width = cols; tmp.height = bins;
    tmp.getContext("2d").putImageData(img, 0, 0);
    g.imageSmoothingEnabled = false;
    g.drawImage(tmp, left, top, w - left - 6, h - top - 18);
    g.fillStyle = css("--md-default-fg-color--light", "#666");
    g.font = "11px sans-serif";
    for (var f = 0; f <= fmax; f += 5000) {
      var yy = top + (h - top - 18) * (1 - f / fmax);
      g.fillText((f / 1000) + "k", 2, yy + 4);
    }
    axes(g, c, title, "time →", "");
  }
  function scatter(c, pts, ideal, title) {
    var g = ctxOf(c), w = c.width, h = c.height, s = Math.min(w, h) / 2 - 24;
    var cx = w / 2, cy = h / 2 + 8, sc = s / 2;
    g.strokeStyle = css("--md-default-fg-color--lightest", "#ccc");
    g.beginPath(); g.moveTo(cx - s, cy); g.lineTo(cx + s, cy);
    g.moveTo(cx, cy - s); g.lineTo(cx, cy + s); g.stroke();
    g.fillStyle = css("--md-primary-fg-color", "#3f51b5");
    g.globalAlpha = 0.45;
    for (var i = 0; i < pts.length; i += 2) {
      g.fillRect(cx + pts[i] * sc - 1, cy - pts[i + 1] * sc - 1, 2, 2);
    }
    g.globalAlpha = 1;
    g.strokeStyle = css("--md-accent-fg-color", "#00bcd4");
    g.lineWidth = 2;
    for (i = 0; i < ideal.length; i += 2) {
      g.beginPath(); g.arc(cx + ideal[i] * sc, cy - ideal[i + 1] * sc, 5, 0, 2 * Math.PI); g.stroke();
    }
    g.lineWidth = 1;
    axes(g, c, title, "I", "Q");
  }

  // ---------- CSS (css_modulate.c) ----------
  function cssChirp(f0, B, T, fs) {
    var n = Math.floor(T * fs + 0.5), s = new Float64Array(n);
    for (var i = 0; i < n; i++) {
      var t = i / fs;
      s[i] = 0.8 * Math.cos(2 * Math.PI * (f0 + (B / (2 * T)) * t) * t);
    }
    return s;
  }
  function renderCss() {
    var fs = +$("css-fs").value, f0 = +$("css-f0").value, B = +$("css-bw").value;
    var T = +$("css-t").value / 1000, snr = +$("css-snr").value;
    var bits = ($("css-bits").value || "").replace(/[^01]/g, "").slice(0, 32);
    $("css-f0-o").value = (f0 / 1000).toFixed(1) + " kHz";
    $("css-bw-o").value = (B / 1000).toFixed(1) + " kHz";
    $("css-t-o").value = (T * 1000).toFixed(0) + " ms";
    $("css-snr-o").value = snr + " dB";
    if (f0 + B > fs / 2) {
      $("css-stats").textContent = "f0 + B exceeds Nyquist (" + fs / 2 + " Hz); the native validator would reject this.";
      return;
    }
    var up = cssChirp(f0, B, T, fs), down = cssChirp(f0, -B, T, fs), seq = [];
    for (var i = 0; i < 8; i++) seq.push(up);
    seq.push(down, down);
    for (i = 0; i < bits.length; i++) seq.push(bits[i] === "1" ? down : up);
    var x = new Float64Array(seq.length * up.length);
    for (i = 0; i < seq.length; i++) x.set(seq[i], i * up.length);
    var y = addNoise(x, snr, rng(7));
    var zoom = y.subarray(0, Math.min(y.length, Math.round(fs * 0.002)));
    linePlot($("css-wave"), zoom, "First 2 ms of the frame (up-chirp start, with noise)", "t", "amplitude");
    spectrogram($("css-spec"), y, fs, 256, fs / 2, "Spectrogram: 8 up + 2 down preamble, then one chirp per bit");
    var air = (10 + bits.length) * up.length / fs;
    $("css-stats").textContent =
      "Band " + ((f0 - B) / 1000).toFixed(1) + "–" + ((f0 + B) / 1000).toFixed(1) + " kHz · " +
      up.length + " samples/chirp · raw rate " + (1 / T).toFixed(1) + " bit/s · this frame " +
      air.toFixed(2) + " s (" + bits.length + " bits + preamble)";
  }

  // ---------- OFDM (ofdm_modulate.c) ----------
  function renderOfdm() {
    var fs = 44100, N = +$("ofdm-n").value, cp = +$("ofdm-cp").value;
    var qpsk = $("ofdm-mod").value === "qpsk", snr = +$("ofdm-snr").value;
    $("ofdm-snr-o").value = snr + " dB";
    var guard = N / 8, start = guard + 1, end = N / 2 - 1, data = [], pilots = 0, k;
    for (k = start; k <= end; k++) { if ((k - start) % 8 === 0) pilots++; else data.push(k); }
    var r = rng(11), nsym = 150, pts = [], bitErr = 0, bits = 0;
    var es = 1, n0 = es / Math.pow(10, snr / 10), sd = Math.sqrt(n0 / 2), a = Math.SQRT1_2;
    var tx = new Float64Array((nsym > 8 ? 8 : nsym) * (N + cp));
    for (var s = 0; s < nsym; s++) {
      var Xr = new Float64Array(N), Xi = new Float64Array(N);
      for (var d = 0; d < data.length; d++) {
        var b1 = r() < 0.5 ? 1 : 0, b2 = r() < 0.5 ? 1 : 0, ir, ii;
        if (qpsk) { // qpsk_map: 00 -> (+,+), 01 -> (-,+), 11 -> (-,-), 10 -> (+,-)
          ir = b2 ? -a : a; ii = b1 ? -a : a;
        } else { ir = b1 ? 1 : -1; ii = 0; }   // bpsk_map: 0 -> -1, 1 -> +1
        Xr[data[d]] = ir; Xi[data[d]] = ii;
        var yr = ir + sd * gauss(r), yi = ii + sd * gauss(r);
        pts.push(yr, yi);
        if (qpsk) {
          bitErr += ((yr > 0) !== (ir > 0)) + ((yi > 0) !== (ii > 0)); bits += 2;
        } else { bitErr += ((yr > 0) !== (ir > 0)) ? 1 : 0; bits += 1; }
      }
      for (k = start; k <= end; k += 8) { Xr[k] = 1; Xi[k] = 0; } // pilots
      if (s < 8) { // time-domain symbol: Hermitian IFFT, 1/sqrt(N), CP
        var re = new Float64Array(N), im = new Float64Array(N);
        for (k = 1; k < N / 2; k++) { re[k] = Xr[k]; im[k] = -Xi[k]; re[N - k] = Xr[k]; im[N - k] = Xi[k]; }
        fft(re, im); // conj-input FFT == N * conj(IFFT); real part is what we need
        var off = s * (N + cp);
        for (var n = 0; n < N; n++) tx[off + cp + n] = re[n] / Math.sqrt(N);
        for (n = 0; n < cp; n++) tx[off + n] = tx[off + N + n];
      }
    }
    var ideal = qpsk ? [a, a, -a, a, -a, -a, a, -a] : [1, 0, -1, 0];
    scatter($("ofdm-const"), pts, ideal, (qpsk ? "QPSK" : "BPSK") + " data subcarriers, Es/N0 = " + snr + " dB");
    spectrogram($("ofdm-spec"), addNoise(tx, 40, rng(3)), fs, 256, fs / 2,
      "Spectrogram of 8 OFDM symbols (bins " + start + "–" + end + ")");
    var ebn0 = Math.pow(10, snr / 10) / (qpsk ? 2 : 1);
    var theory = qfunc(Math.sqrt(2 * ebn0));
    var df = fs / N, rate = data.length * (qpsk ? 2 : 1) / ((N + cp) / fs);
    $("ofdm-stats").textContent =
      "Δf " + df.toFixed(1) + " Hz · band " + (start * df / 1000).toFixed(1) + "–" +
      (end * df / 1000).toFixed(1) + " kHz · " + data.length + " data + " + pilots + " pilot bins · raw rate " +
      (rate / 1000).toFixed(1) + " kbit/s · simulated BER " + (bitErr / bits).toExponential(2) +
      " (" + bits + " bits) vs theory " + theory.toExponential(2);
  }

  function exportPng(id) {
    var a = document.createElement("a");
    a.download = id + ".png";
    a.href = $(id).toDataURL("image/png");
    a.click();
  }

  function init() {
    var root = $("sw-lab");
    if (!root || root.dataset.ready) return;
    root.dataset.ready = "1";
    ["css-fs", "css-f0", "css-bw", "css-t", "css-snr", "css-bits"].forEach(function (id) {
      $(id).addEventListener("input", renderCss);
    });
    ["ofdm-n", "ofdm-cp", "ofdm-mod", "ofdm-snr"].forEach(function (id) {
      $(id).addEventListener("input", renderOfdm);
    });
    $("sw-math").addEventListener("change", function (e) {
      root.classList.toggle("show-math", e.target.checked);
    });
    Array.prototype.forEach.call(root.querySelectorAll("button[data-export]"), function (b) {
      b.addEventListener("click", function () { exportPng(b.dataset.export); });
    });
    renderCss();
    renderOfdm();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
