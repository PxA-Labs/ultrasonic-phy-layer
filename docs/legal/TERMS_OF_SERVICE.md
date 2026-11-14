# Terms of Service (DRAFT)

!!! danger "DRAFT — requires legal review before publication"
    This is an engineering draft, not legal advice. Governing law, liability language and the relationship to the Apache License 2.0 must be decided by a qualified lawyer before publication. Items marked *TODO* are open.

**App:** Soundwave · **Publisher:** PxA Labs (*TODO: legal entity, address*) · **Effective date:** *TODO*

## 1. Acceptance

By installing or using Soundwave ("the app") you agree to these terms. If you do not agree, do not use the app.

## 2. Open-source licence

The app's source code is published under the Apache License 2.0 at <https://github.com/PxA-Labs/ultrasonic-phy-layer>. These terms cover your use of the builds distributed by PxA Labs (for example through app stores). They do not restrict any rights the Apache License 2.0 grants you for the source code. *TODO (legal): confirm how these terms and the licence interact, and list third-party notices (KissFFT, miniaudio, Flutter packages).*

## 3. What the app is, and is not

Soundwave is an **experimental** tool for short-range data transfer over sound. It is **not** a secure, reliable or certified communication channel:

- Transmissions are **not encrypted or authenticated**. Others nearby can receive, record or imitate them.
- Delivery is **not guaranteed**. Messages and files can be lost, delayed or, rarely, corrupted.
- Do not use the app for emergency, safety-critical, medical or financial communication, or to send sensitive personal data, passwords or confidential information.

## 4. Acceptable use

You agree not to use the app to:

- transmit content that is unlawful, harassing, or infringes others' rights;
- interfere with other people's devices, hearing aids, assistive or medical equipment, or with animals, or play sound in places where that is prohibited;
- track, profile or covertly signal to people without their knowledge or consent;
- send malicious files.

## 5. Sound exposure and hearing safety

The app plays high-frequency sound at the device volume **you** choose. The app does **not** measure or limit the sound pressure level (SPL) that your speaker produces. The project's design target is no more than 80 dB SPL at 1 m (see the PRD), but this has **not** been verified on any device.

- Use the lowest volume that works, and do not hold a transmitting device close to anyone's ears.
- Some people (especially children and young adults) and many animals can hear frequencies that adults cannot. Stop if anyone reports discomfort, headaches or ringing in the ears.
- In OFDM mode the current signal extends well into the audible range (roughly 5.5–22 kHz).

*TODO (legal/acoustics): decide whether to state an SPL limit after it has been measured (see the [hardware profiling plan](../testing/HARDWARE_PROFILING_PLAN.md)).*

## 6. Your content

You are responsible for what you transmit and for files you receive and open. Received files are saved as received, without scanning.

## 7. No warranty

The app is provided **"as is" and "as available"**, without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose and non-infringement, to the extent permitted by law. *TODO (legal): jurisdiction-specific wording.*

## 8. Limitation of liability

To the extent permitted by law, PxA Labs and the contributors are not liable for any indirect, incidental or consequential damages, or for lost data, arising from the use of or inability to use the app. *TODO (legal): caps, consumer-law carve-outs.*

## 9. Privacy

See the [Privacy Policy](PRIVACY_POLICY.md).

## 10. Changes and termination

We may update these terms. Material changes will be announced in the release notes and take effect from the date stated above. You may stop using the app at any time by uninstalling it.

## 11. Governing law and contact

*TODO (legal): governing law, venue, contact address.*
