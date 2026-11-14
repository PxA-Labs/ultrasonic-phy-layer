# Privacy Policy (DRAFT)

!!! danger "DRAFT — requires legal review before publication"
    This is an engineering draft written from the app's source code (branch `integration/overnight`, November 2026). It is **not legal advice** and must be reviewed by a qualified lawyer, completed (see the *TODO* items), and re-checked against the shipped build before it is published or linked from a store listing.

**App:** Soundwave (Android package `com.pxalabs.soundwave`; Windows, macOS and Linux desktop builds)
**Publisher:** PxA Labs. *TODO: legal entity name, postal address, contact e-mail.*
**Effective date:** *TODO*

## Summary

- Soundwave has **no accounts, no servers, no analytics, no advertising and no crash reporting**. The app does not send any data over the internet.
- The **microphone** is used only while you have the receiver turned on, to detect and decode Soundwave signals **on your device**.
- Everything the app stores stays **on your device** until you delete it or choose to share it.
- **Messages and files you transmit are broadcast as sound and are not encrypted.** Anyone nearby with a compatible receiver can pick them up.

## 1. What the app does

Soundwave turns text and small files into high-frequency sound played through your device's speaker, and turns that sound back into data using the microphone of a nearby device. It works without an internet connection, Bluetooth or pairing.

## 2. Data the app processes

| Data | When | Where it goes | Kept for |
|---|---|---|---|
| Microphone audio | Only while the receiver is on ("Start Listening"), or while you record | Processed in memory on your device. The last ~10 seconds are held in memory so you can choose to save a sample | Discarded continuously, unless you record or save it (below) |
| Recordings (WAV) | Only when you tap Record | App's private documents folder (`soundwave/recordings/`) | Until you clear them in the app or uninstall it |
| Signal samples | Only when you tap *Save Signal Sample* | `soundwave/samples/`: about 10 s of audio, plus a small JSON file with your optional note and the most recently decoded message | Until cleared or uninstalled |
| Decoded messages | When the receiver decodes a message | In memory only (last 100) | Until the app closes, unless you export them |
| Exported message logs (JSON/CSV/TXT) | Only when you tap *Export* | `soundwave/exports/`, then the system share sheet | Until cleared or uninstalled |
| Received files | When another device sends you a file | `Soundwave/received/` in the app's documents folder | Until you delete them or uninstall |
| Files you send or import | Only files you pick with the system file picker | Read into memory to transmit or decode; the app does not copy them elsewhere | Not retained |
| Settings | When you change them | Local app preferences (theme, modem settings, whether you have seen the tutorial) | Until changed or uninstalled |
| Link-layer node ID | Each app start | A random 16-bit number in memory, sent inside transmitted frames so devices can tell senders apart | Not stored; a new one is chosen at every start |

The app does not collect your name, contacts, location, device identifiers or advertising ID.

## 3. Network use

The app has no code that opens network connections, and it uses no analytics, advertising or crash-reporting SDKs. The Android release manifest of the app does not request the `INTERNET` permission. *TODO before publication: confirm this against the **merged** manifest of the release build (third-party plugins can add permissions), for example with `aapt dump permissions app-release.apk`.*

## 4. Sharing

The app shares data only when **you** start it:

- **Share sheet:** exported message logs are handed to the app you pick in the system share sheet. That app's privacy policy then applies.
- **Acoustic transmission:** anything you send is broadcast as sound. It is **not encrypted or authenticated**. Any nearby device running Soundwave or a compatible decoder can receive it, and anyone can record the sound. Do not send passwords, personal data or other sensitive information.
- **Receiving:** while the receiver is on, the app decodes any compatible transmission it hears, including transmissions from people you do not know. Received files are saved to the app's folder; open them with the same care as any downloaded file.

## 5. Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | Microphone (`RECORD_AUDIO`) | To receive signals. Requested at runtime; the app can still transmit without it |
| Android | Modify audio settings (`MODIFY_AUDIO_SETTINGS`) | Declared in the manifest for audio configuration. A normal permission, granted at install without a prompt |
| macOS | Microphone (sandbox audio-input entitlement, `NSMicrophoneUsageDescription`) | To receive signals |
| macOS | User-selected file read/write | To import and export files you choose |
| Windows (MSIX) | Microphone capability | To receive signals |

## 6. Your choices and deleting data

- Turn the receiver off at any time; the microphone then stops.
- Revoke microphone access in your system settings.
- Delete recordings, exports or samples in the app (**Clear All**). Delete received files with your file manager.
- Uninstalling the app removes its private folders and preferences (on desktop platforms, the documents folder may need to be removed manually). *TODO: confirm per platform.*

Because the publisher receives no data, there is no data held by PxA Labs to access, correct or delete.

## 7. Children

*TODO (legal): state the target audience and any age restrictions. The app collects no personal data, but it is a general-purpose tool and is not designed for children.*

## 8. Security

Data stays in the app's storage area and is protected by your operating system's normal app isolation. Acoustic transmissions are not encrypted (see section 4).

## 9. Changes

We will update this policy if the app's data handling changes (for example, if an optional network feature is ever added), and change the effective date above.

## 10. Contact

*TODO: contact e-mail or address for privacy questions.*
