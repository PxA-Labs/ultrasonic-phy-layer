#!/usr/bin/env python3
"""Frame/bit error measurements for Soundwave using soundwave-cli.

Standard library only (Python 3.8+). Drives the `soundwave-cli` binary built
from native/tools/soundwave_cli (see docs/CLI_GUIDE.md); it does not
reimplement any DSP.

Workflow (see docs/testing/FIELD_TEST_PLAN.md):

  1. generate  - build K known test frames and a playlist WAV
                 (lead-in silence, then frame/gap/frame/gap...) plus a
                 manifest.json describing them.
  2. (field)   - play playlist.wav on the transmitter, record on the
                 receiver (16-bit PCM or 32-bit float WAV, same sample rate).
  3. decode    - cut the recording into one window per frame slot, run
                 `soundwave-cli demodulate` on each, match decoded payloads to
                 the manifest and write per-frame CSV + a JSON summary.
  4. simulate  - offline AWGN baseline: push every generated frame through
                 `soundwave-cli simulate --snr X` and decode it. Results are
                 SIMULATED and must never be reported as field measurements.

What can be measured with the CLI as it exists today:

  * FER  - frames not delivered (sync, RS or CRC failure) / frames sent.
  * Residual BER - bit errors in delivered payloads / delivered payload bits.
    A delivered frame has passed RS decoding and CRC-32, so this is normally
    0; with 0 errors in n bits the 95 % upper confidence bound is 3/n
    ("rule of three").
  * RS corrections - symbols (bytes) corrected per delivered frame, a lower
    bound on the pre-FEC byte error rate (frames that failed are excluded).

The CLI does not expose raw (pre-FEC) demodulated bits, so a true channel BER
cannot be computed from its output.
"""

import argparse
import json
import math
import os
import random
import re
import shutil
import string
import struct
import subprocess
import sys
import tempfile
import wave
from array import array

PAYLOAD_RE = re.compile(r"^SW(\d{4})\|")
SNR_RE = re.compile(r"snr = (-?[0-9.]+|nan|inf|-inf) dB")
CORR_RE = re.compile(r"Errors corrected: (\d+)")
ALPHABET = string.ascii_letters + string.digits
CLI_MAX_PAYLOAD = 217  # 223 RS data bytes - 4 CRC - 2 length (main.c)
RS_PARITY = 32
CLI_HEADER = 6  # CRC-32 + 16-bit length


# --------------------------------------------------------------------------
# WAV helpers (PCM 8/16/24/32-bit and IEEE float 32-bit; first channel only)
# --------------------------------------------------------------------------

def read_wav(path):
    """Returns (samples as list of floats in [-1, 1], sample_rate)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path}: not a RIFF/WAVE file")
    pos = 12
    fmt = None
    pcm = None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body, 0)
        elif cid == b"data":
            pcm = body
        pos += 8 + size + (size & 1)
    if fmt is None or pcm is None:
        raise ValueError(f"{path}: missing fmt or data chunk")
    audio_format, channels, rate, _, block_align, bits = fmt
    if audio_format == 0xFFFE and len(fmt) >= 6:  # WAVE_FORMAT_EXTENSIBLE
        audio_format = 3 if bits == 32 and _extensible_is_float(data) else 1
    width = bits // 8
    frames = len(pcm) // block_align
    out = [0.0] * frames
    if audio_format == 3 and bits == 32:
        for i in range(frames):
            out[i] = struct.unpack_from("<f", pcm, i * block_align)[0]
    elif audio_format == 1 and bits in (8, 16, 24, 32):
        scale = float(1 << (bits - 1))
        for i in range(frames):
            o = i * block_align
            if bits == 8:
                v = pcm[o] - 128
            else:
                v = int.from_bytes(pcm[o:o + width], "little", signed=True)
            out[i] = v / scale
    else:
        raise ValueError(f"{path}: unsupported WAV format {audio_format}/{bits}-bit")
    return out, rate


def _extensible_is_float(data):
    # Sub-format GUID starts with the format code (3 = IEEE float).
    i = data.find(b"fmt ")
    return i >= 0 and struct.unpack_from("<H", data, i + 8 + 24)[0] == 3


def write_wav16(path, samples, rate):
    pcm = array("h", (max(-32768, min(32767, int(round(s * 32767.0)))) for s in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


# --------------------------------------------------------------------------
# soundwave-cli wrappers
# --------------------------------------------------------------------------

def modem_args(params):
    args = ["--mode", params["mode"]]
    for key, flag in (("fft", "--fft"), ("cp", "--cp"), ("freq", "--freq"),
                      ("bw", "--bw"), ("amp", "--amp")):
        if params.get(key) is not None:
            args += [flag, str(params[key])]
    return args


def cli_modulate(cli, params, text, out_path):
    cmd = [cli, "modulate"] + modem_args(params) + ["--input", text, "--output", out_path]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"modulate failed ({res.returncode}): {res.stderr.strip()}")


def cli_demodulate(cli, params, wav_path):
    """Returns dict(ok, payload, corrected, snr_db, stderr)."""
    cmd = [cli, "demodulate"] + modem_args(params) + ["--input", wav_path]
    if params.get("equalizer"):
        cmd += ["--equalizer", params["equalizer"]]
    res = subprocess.run(cmd, capture_output=True)
    err = res.stderr.decode("utf-8", "replace")
    snr = SNR_RE.search(err)
    corr = CORR_RE.search(err)
    payload = res.stdout
    if payload.endswith(b"\n"):
        payload = payload[:-1]  # the CLI appends one newline
    return {
        "ok": res.returncode == 0,
        "payload": payload if res.returncode == 0 else b"",
        "corrected": int(corr.group(1)) if corr else None,
        "snr_db": float(snr.group(1)) if snr else None,
        "stderr": err.strip(),
    }


def cli_simulate(cli, in_path, snr_db, out_path):
    cmd = [cli, "simulate", "--input", in_path, "--snr", str(snr_db), "--output", out_path]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"simulate failed: {res.stderr.strip()}")


# --------------------------------------------------------------------------
# Metrics
# --------------------------------------------------------------------------

def bit_errors(expected, got):
    errs = 0
    for a, b in zip(expected, got):
        errs += bin(a ^ b).count("1")
    return errs + 8 * abs(len(expected) - len(got))


def summarize(manifest, rows):
    payload_bits = manifest["payload_bytes"] * 8
    codeword = manifest["payload_bytes"] + CLI_HEADER + RS_PARITY
    sent = manifest["frames"]
    delivered = [r for r in rows if r["decoded"]]
    n_bits = len(delivered) * payload_bits
    errs = sum(r["bit_errors"] for r in delivered)
    corr = sum(r["rs_corrected"] or 0 for r in delivered)
    snrs = [r["snr_db"] for r in delivered
            if r["snr_db"] is not None and math.isfinite(r["snr_db"])]
    return {
        "frames_sent": sent,
        "frames_delivered": len(delivered),
        "fer": (sent - len(delivered)) / sent if sent else None,
        "payload_bits_delivered": n_bits,
        "residual_bit_errors": errs,
        "residual_ber": errs / n_bits if n_bits else None,
        "residual_ber_95_upper": (3.0 / n_bits if errs == 0 else None) if n_bits else None,
        "rs_symbols_corrected": corr,
        "rs_symbol_error_rate_delivered": corr / (len(delivered) * codeword) if delivered else None,
        "median_cli_snr_db": sorted(snrs)[len(snrs) // 2] if snrs else None,
    }


def write_rows(path, rows):
    cols = ["frame", "decoded", "bit_errors", "rs_corrected", "snr_db", "window_start_s", "note"]
    with open(path, "w", encoding="utf-8") as f:
        f.write(",".join(cols) + "\n")
        for r in rows:
            f.write(",".join("" if r.get(c) is None else str(r.get(c)) for c in cols) + "\n")


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def make_payload(rng, index, size):
    head = f"SW{index:04d}|"
    if size < len(head) + 1:
        raise ValueError(f"--payload-bytes must be >= {len(head) + 1}")
    return head + "".join(rng.choice(ALPHABET) for _ in range(size - len(head)))


def cmd_generate(a):
    if not 1 <= a.payload_bytes <= CLI_MAX_PAYLOAD:
        sys.exit(f"--payload-bytes must be 1..{CLI_MAX_PAYLOAD}")
    os.makedirs(a.out, exist_ok=True)
    params = {"mode": a.mode, "fft": a.fft, "cp": a.cp, "freq": a.freq, "bw": a.bw,
              "amp": a.amp, "equalizer": a.equalizer}
    rng = random.Random(a.seed)
    payloads, files = [], []
    rate = None
    frame_len = 0
    for i in range(a.frames):
        text = make_payload(rng, i, a.payload_bytes)
        path = os.path.join(a.out, f"frame_{i:04d}.wav")
        cli_modulate(a.cli, params, text, path)
        samples, r = read_wav(path)
        if rate is None:
            rate = r
        frame_len = max(frame_len, len(samples))
        payloads.append(text)
        files.append(os.path.basename(path))
    gap = int(round(a.gap * rate))
    lead = int(round(a.lead_in * rate))
    playlist = [0.0] * lead
    for name in files:
        s, _ = read_wav(os.path.join(a.out, name))
        playlist += s + [0.0] * (frame_len - len(s)) + [0.0] * gap
    write_wav16(os.path.join(a.out, "playlist.wav"), playlist, rate)
    manifest = {
        "tool": "ber_sweep.py", "version": 1, "params": params, "seed": a.seed,
        "frames": a.frames, "payload_bytes": a.payload_bytes, "payloads": payloads,
        "frame_files": files, "sample_rate": rate, "frame_samples": frame_len,
        "gap_samples": gap, "lead_in_samples": lead,
        "playlist_seconds": len(playlist) / rate,
    }
    with open(os.path.join(a.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"{a.frames} frames x {a.payload_bytes} B, frame {frame_len / rate:.2f} s, "
          f"playlist {len(playlist) / rate:.1f} s -> {a.out}")
    if a.verify:
        bad = [n for n in files
               if not cli_demodulate(a.cli, params, os.path.join(a.out, n))["ok"]]
        if bad:
            sys.exit(f"self-check failed: clean frames did not decode: {bad}")
        print("self-check: every clean frame decodes")


def load_manifest(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def decode_windows(cli, manifest, samples, rate, offset, first, count, tmp):
    """Decodes `count` slot windows starting at slot `first`; returns results."""
    slot = manifest["frame_samples"] + manifest["gap_samples"]
    win = slot + manifest["gap_samples"]
    out = []
    for j in range(first, first + count):
        start = offset + j * slot
        if start >= len(samples):
            break
        seg = samples[max(0, start):start + win]
        path = os.path.join(tmp, f"win_{j:05d}.wav")
        write_wav16(path, seg, rate)
        res = cli_demodulate(cli, manifest["params"], path)
        res["window_start_s"] = round(max(0, start) / rate, 3)
        out.append(res)
    return out


def match(manifest, results):
    """Maps decoded payloads to manifest frames; returns per-frame rows."""
    rows = {i: {"frame": i, "decoded": 0, "bit_errors": None, "rs_corrected": None,
                "snr_db": None, "window_start_s": None, "note": ""}
            for i in range(manifest["frames"])}
    for r in results:
        if not r["ok"]:
            continue
        text = r["payload"].decode("ascii", "replace")
        m = PAYLOAD_RE.match(text)
        if not m or int(m.group(1)) not in rows:
            continue  # CRC passed but not one of ours (should not happen)
        i = int(m.group(1))
        if rows[i]["decoded"]:
            continue  # same frame seen in two windows
        expected = manifest["payloads"][i].encode("ascii")
        rows[i].update(decoded=1, bit_errors=bit_errors(expected, r["payload"]),
                       rs_corrected=r["corrected"], snr_db=r["snr_db"],
                       window_start_s=r["window_start_s"])
    return [rows[i] for i in sorted(rows)]


def cmd_decode(a):
    manifest = load_manifest(a.manifest)
    samples, rate = read_wav(a.recording)
    if rate != manifest["sample_rate"]:
        msg = (f"recording is {rate} Hz but frames were generated at "
               f"{manifest['sample_rate']} Hz")
        if manifest["params"]["mode"] == "ofdm":
            sys.exit(msg + "; OFDM needs the same rate (resample first)")
        print("WARNING: " + msg, file=sys.stderr)
    slot = manifest["frame_samples"] + manifest["gap_samples"]
    tmp = tempfile.mkdtemp(prefix="sw_ber_")
    try:
        # Align the slot grid: try offsets one half-gap apart over one slot and
        # keep the one that decodes most of the first `probe` slots.
        step = max(1, manifest["gap_samples"] // 2)
        probe = min(a.probe, manifest["frames"])
        best, best_n = 0, -1
        for off in range(-manifest["gap_samples"], slot, step):
            res = decode_windows(a.cli, manifest, samples, rate, off, 0, probe + 1, tmp)
            n = sum(1 for r in match(manifest, res) if r["decoded"])
            if n > best_n:
                best, best_n = off, n
            if n >= probe:
                break
        n_slots = manifest["frames"] + 2
        results = decode_windows(a.cli, manifest, samples, rate, best, 0, n_slots, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    rows = match(manifest, results)
    summary = summarize(manifest, rows)
    summary.update(recording=os.path.basename(a.recording), grid_offset_s=best / rate,
                   label=a.label or "", kind="FIELD (recorded)")
    report(a.out, rows, summary)


def cmd_simulate(a):
    manifest = load_manifest(a.manifest)
    base = os.path.dirname(os.path.abspath(a.manifest))
    snrs = [float(x) for x in a.snr.split(",")]
    tmp = tempfile.mkdtemp(prefix="sw_sim_")
    table = []
    try:
        for snr in snrs:
            results = []
            for name in manifest["frame_files"]:
                noisy = os.path.join(tmp, "noisy.wav")
                cli_simulate(a.cli, os.path.join(base, name), snr, noisy)
                r = cli_demodulate(a.cli, manifest["params"], noisy)
                r["window_start_s"] = 0.0
                results.append(r)
            rows = match(manifest, results)
            s = summarize(manifest, rows)
            s.update(snr_db_set=snr, kind="SIMULATED (soundwave-cli simulate, AWGN)")
            table.append(s)
            print(f"SNR {snr:6.1f} dB: delivered {s['frames_delivered']}/{s['frames_sent']}"
                  f"  FER={s['fer']:.3f}  residual BER={s['residual_ber']}"
                  f"  RS corrections={s['rs_symbols_corrected']}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(table, f, indent=2)
    if a.min_delivered_at is not None:
        snr, need = a.min_delivered_at
        for s in table:
            if s["snr_db_set"] >= snr and s["frames_delivered"] < need * s["frames_sent"]:
                sys.exit(f"FAIL: only {s['frames_delivered']}/{s['frames_sent']} frames "
                         f"delivered at {s['snr_db_set']} dB")


def report(out, rows, summary):
    if out:
        os.makedirs(out, exist_ok=True)
        write_rows(os.path.join(out, "frames.csv"), rows)
        with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)
    print(json.dumps(summary, indent=2))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--cli", default=os.environ.get("SOUNDWAVE_CLI", "soundwave-cli"),
                   help="path to the soundwave-cli binary (or $SOUNDWAVE_CLI)")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="create test frames, playlist.wav and manifest.json")
    g.add_argument("--mode", choices=["css", "ofdm"], required=True)
    g.add_argument("--frames", type=int, default=20)
    g.add_argument("--payload-bytes", type=int, default=64)
    g.add_argument("--gap", type=float, default=1.0, help="silence between frames, s")
    g.add_argument("--lead-in", type=float, default=2.0, help="silence before frame 0, s")
    g.add_argument("--seed", type=int, default=1)
    g.add_argument("--fft", type=int)
    g.add_argument("--cp", type=int)
    g.add_argument("--freq", type=float)
    g.add_argument("--bw", type=float)
    g.add_argument("--amp", type=float)
    g.add_argument("--equalizer", choices=["zf", "mmse"])
    g.add_argument("--verify", action="store_true", help="decode every clean frame once")
    g.add_argument("--out", required=True)
    g.set_defaults(func=cmd_generate)

    d = sub.add_parser("decode", help="decode a field recording of playlist.wav")
    d.add_argument("--manifest", required=True)
    d.add_argument("--recording", required=True)
    d.add_argument("--probe", type=int, default=2, help="slots used to align the grid")
    d.add_argument("--label", help="free text stored in summary.json (e.g. test id)")
    d.add_argument("--out", help="directory for frames.csv and summary.json")
    d.set_defaults(func=cmd_decode)

    s = sub.add_parser("simulate", help="AWGN baseline through soundwave-cli simulate")
    s.add_argument("--manifest", required=True)
    s.add_argument("--snr", default="0,3,6,10,15,20", help="comma-separated SNRs in dB")
    s.add_argument("--out", help="JSON file for the table")
    s.add_argument("--min-delivered-at", nargs=2, type=float, metavar=("SNR_DB", "FRACTION"),
                   help="exit non-zero if fewer frames are delivered at or above SNR_DB")
    s.set_defaults(func=cmd_simulate)

    a = p.parse_args(argv)
    if shutil.which(a.cli) is None and not os.path.isfile(a.cli):
        sys.exit(f"soundwave-cli not found: {a.cli} (pass --cli or set SOUNDWAVE_CLI)")
    a.func(a)


if __name__ == "__main__":
    main()
