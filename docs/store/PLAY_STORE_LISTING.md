# Google Play Store Listing (DRAFT)

!!! danger "DRAFT — requires legal review before publication"
    The listing text must be reviewed (legal and marketing) and checked against the build that is actually submitted. Every claim below is limited to features present in the code today. Do **not** add range, speed or reliability claims until the [field tests](../testing/FIELD_TEST_PLAN.md) have produced measured results.

## Store metadata

| Field | Draft value | Notes |
|---|---|---|
| App name (≤ 30 chars) | `Soundwave: Data over Sound` | 26 characters |
| Package | `com.pxalabs.soundwave` | From `android/app/build.gradle.kts` |
| Category | Tools | Issue #97 suggests Tools or Communication. *Tools* fits an experimental modem better and avoids messaging-app expectations |
| Tags | Tools, Utilities | *TODO: choose from the Play Console tag list* |
| Contact e-mail | *TODO* | Required |
| Website | `https://pxa-labs.github.io/ultrasonic-phy-layer/` | Docs site (after deploy) |
| Privacy policy URL | `https://pxa-labs.github.io/ultrasonic-phy-layer/legal/PRIVACY_POLICY/` | Publish only **after** legal review. The URL is valid once the docs site is deployed from `main` |
| Price | Free, no in-app purchases, no ads | |

## Short description (≤ 80 characters)

> Send text and small files between nearby devices using high-frequency sound.

(76 characters.)

## Full description (≤ 4000 characters)

> **Soundwave sends data through the air as sound.** Type a message or pick a small file, and Soundwave plays it as a high-frequency signal through your speaker. A nearby phone or computer running Soundwave picks it up with its microphone and decodes it. No internet, Bluetooth, pairing or account is needed.
>
> **Two modulation modes**
> • CSS (chirp spread spectrum): slow but robust. Each frequency sweep carries 6–10 bits, in the 18–20 kHz range with the default settings.
> • OFDM: much faster, using many subcarriers at once. In the current version its signal is clearly audible.
> • Presets for a robust long-range setup and a high-speed OFDM setup, plus full manual control of frequency, sweep, spreading factor, FFT size, cyclic prefix and equalizer.
>
> **Built-in error protection**
> Every frame carries a CRC-32 checksum and optional Reed-Solomon error correction. Longer messages and files are split into fragments and reassembled, with optional automatic retransmission (ARQ) when both devices enable it.
>
> **See the signal**
> Live spectrum analyzer, waterfall spectrogram, waveform view and OFDM constellation diagram, with an estimated SNR for every received message.
>
> **Record, import and export**
> Record what the microphone hears as WAV, import WAV/PCM files and decode them offline, save signal samples, and export your message log as JSON, CSV or TXT.
>
> **Private by design**
> No accounts, no ads, no analytics and no crash reporting, and the app does not connect to the internet. Audio is processed on your device and nothing leaves it unless you share it. Note that transmissions are broadcast as sound and are **not encrypted**: anyone nearby with a compatible receiver can hear them, so do not send sensitive information.
>
> **Good to know**
> • Range and speed depend heavily on your speaker, microphone, volume and room. Start with the devices close together.
> • Most adults hear little of the CSS band, but children and pets may.
> • Soundwave is experimental, open-source software (Apache 2.0): github.com/PxA-Labs/ultrasonic-phy-layer

(About 2,000 characters. *TODO: recount after edits; Play counts characters, not bytes.*)

## Graphics checklist (issue #97)

| Asset | Spec | Status |
|---|---|---|
| App icon | 512 × 512 PNG, 32-bit, ≤ 1 MB | *TODO: no 512 px store icon in the repo; check whether the launcher icons in `android/app/src/main/res/mipmap-*` are final* |
| Feature graphic | 1024 × 500 JPG/PNG | *TODO* |
| Phone screenshots | ≥ 2 required (issue asks for 4+), 16:9 or 9:16, 320–3840 px per side | *TODO: Dashboard (message sent and received), Monitor (spectrum and waterfall), Settings (presets), File transfer* |
| Tablet screenshots | Issue asks for 2+ (10") | *TODO* |

Screenshots must come from a real build. Do not mock up UI that does not exist.

## Content rating (IARC questionnaire): draft answers

| Topic | Draft answer | Basis |
|---|---|---|
| Violence, sexuality, language, controlled substances, gambling | No | Utility app with no such content |
| User-generated content shared with other users | **Yes, review carefully.** Users can broadcast arbitrary text and files acoustically to nearby devices. There is no server, moderation, account or contact list | Transmission is local and unmoderated. *TODO (legal): decide the answer to the "users can interact / exchange content" questions* |
| Shares user location | No | No location access |
| Digital purchases | No | |
| Unrestricted internet access / web browsing | No | No network code |

## Pre-submission checklist

- [ ] Legal review of the privacy policy, terms and this listing
- [ ] Privacy policy published at a public URL (docs site deployed from `main`)
- [ ] Merged release manifest permissions checked (`aapt dump permissions`). Data safety answers updated if anything beyond `RECORD_AUDIO` / `MODIFY_AUDIO_SETTINGS` appears
- [ ] Release signing secrets configured (`ANDROID_KEYSTORE_*`, see [CI/CD](../CI_CD.md)). Unsigned or debug-signed builds cannot be uploaded
- [ ] `targetSdk` meets the current Play requirement (it comes from the Flutter SDK default)
- [ ] 16 KB page-size alignment confirmed (the `build-android` job checks `libsoundwave.so`)
- [ ] Icon, feature graphic and screenshots
- [ ] [Data safety form](DATA_SAFETY.md) completed
- [x] Privacy policy and terms are readable in the app, offline: Settings → *About & Legal*, and the last onboarding page (issue #97). The app bundles `soundwave_app/assets/legal/`, which a test keeps identical to `docs/legal/`
