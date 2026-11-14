# Using the app

The Soundwave app has three tabs: **Dashboard**, **Monitor** and **Settings**. This page walks through a first transfer and then describes each feature as it exists in the code today.

## First message (two devices)

1. Install and open the app on two devices (see [Build from source](build.md)). On first launch, a five-page tutorial explains the modes and asks for microphone access. You can replay it from **Settings → Show tutorial**.
2. Keep the default settings on **both** devices: CSS mode, 19 kHz start frequency, 2 kHz sweep, 20 ms chirps. Both devices must use the same modem settings.
3. On the receiver, open **Dashboard → Receiver Control → Start Listening**.
4. On the transmitter, type a short message under **Transmission Control** and tap **Send / Modulate & Play**. Set the media volume to a moderate level.
5. Received messages appear under **Received Messages Log**, together with an estimated SNR.

!!! tip "Expect slow CSS frames"
    In the default CSS configuration one chirp carries one bit, so the raw rate is 50 bit/s and even a two-byte message takes about 6 s on air (values computed from the code, see [Signal chain](../architecture/signal-chain.md)). OFDM is much faster, but it currently occupies roughly 5.7–21.9 kHz, which is clearly audible.

Start with the devices close together (tens of centimetres) and increase the distance from there. Range has **not** been measured yet.

## Dashboard

- **Transmission Control**: type text and send it. Short text with ARQ off is sent as a single frame. Longer text uses the link layer (fragmentation).
- **Receiver Control**: start or stop listening, see the last message and the estimated SNR.
- **Quick Actions**: emit a 440 Hz test tone or a chirp preamble, or send a preset message. These are useful for checking the speaker and microphone path.
- **File Transfer**: **Choose File** sends any file through the link layer. Progress is shown per fragment. Received files are listed under **Received Files** and saved to `<app documents>/Soundwave/received/` with sanitized, never-overwriting names. Content is limited to 1 MiB per transfer. In practice, even small files take a long time over CSS.
- **Recording & Signal Files** (while listening):
    - *Record* writes the microphone input to a 16-bit mono WAV in `<app documents>/soundwave/recordings/`.
    - *Import Signal* loads a `.wav`, `.pcm` or `.raw` file and demodulates it offline with the current settings (*Send for Demodulation*).
    - *Save Signal Sample* stores the last 10 s of captured audio plus a JSON sidecar (with the latest decoded message, if any) in `samples/`.
    - *Export All as JSON / CSV / TXT* writes the decoded-message log to `exports/` and opens the system share sheet.
    - *Clear All* buttons delete recordings, exports or samples, and the card shows storage usage.

## Monitor

- **Spectrum analyzer** and **waterfall** (Hann-windowed FFT of the microphone input), with a level meter in dBFS.
- **Constellation** of the equalized OFDM data subcarriers for each received frame (OFDM mode only, while listening).
- **Waveform** view of the raw input.

## Settings

| Group | Settings | Notes |
|---|---|---|
| Presets | *Defaults*, *Long Range (Robust)* (CSS, 18 kHz, 1 kHz sweep, 50 ms chirps), *High Speed (OFDM)* (2048-point FFT, CP 128) | Apply on both devices |
| Modulation | CSS or OFDM | |
| FEC | Reed-Solomon on/off, coding rate 1/2 or 3/4 | The coding-rate value is passed to the native config but **has no effect** in the current DSP code. RS(255,223) is either on or off |
| Audio I/O | Input/output device, playback volume, AGC on/off | AGC is on by default |
| CSS | Spreading factor, chirp duration | The SF value is validated but **does not change the CSS waveform** in the current core. The chirp duration sets the bit rate (1 bit per chirp) |
| OFDM | FFT size, BPSK/QPSK, cyclic prefix, pilots, ZF/MMSE equalizer | |
| Link layer | ARQ on/off, max retries (1/3/5), ACK timeout (200–2000 ms) | With ARQ on, **both** devices must enable it |
| Appearance | System / light / dark theme, replay tutorial | |

Settings are stored locally (`shared_preferences`) and restored on the next launch.

## Privacy in one paragraph

The app does not contact any server, has no analytics and no crash reporting. Audio is processed on the device. **Anything you transmit is broadcast as sound and is not encrypted**: any nearby device running a compatible decoder can receive it. See the draft [privacy policy](../legal/PRIVACY_POLICY.md).

## Troubleshooting

| Symptom | Things to check |
|---|---|
| Nothing is received | Same mode and parameters on both devices. Receiver is listening. Volume is up. Check the Monitor spectrum on the receiver for energy at 17–21 kHz (CSS default) while the transmitter sends |
| "Microphone permission denied" | Grant the permission in system settings (Android), or allow microphone access for the app (macOS privacy settings) |
| Frames are detected but fail CRC | Move the devices closer, reduce the volume if the signal clips, try the *Long Range* preset |
| The receiver hears its own transmissions | Expected: link-layer frames from the device's own node id are ignored |
