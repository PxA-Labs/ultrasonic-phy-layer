# Android Release Signing & Play Console Upload

How Soundwave's Android builds are signed in CI, what the pipeline verifies, and how to upload a release to the Play Console by hand (issue #94, part of #35).

## 1. One-time setup: upload key

Play App Signing is assumed: Google holds the **app signing key**; we sign uploads with our own **upload key**.

```bash
keytool -genkeypair -v -storetype JKS -keystore upload-keystore.jks \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=PxA Labs, O=PxA Labs, C=IN"
```

Keep the keystore and both passwords in the team password manager. Losing the upload key means a reset request to Google.

Add these repository secrets (*Settings → Secrets and variables → Actions*):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 < upload-keystore.jks \| tr -d '\n'` |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password (same as the store password for PKCS12 keystores) |

Optionally pin the certificate with the repository **variable** `ANDROID_SIGNING_CERT_SHA256`. Its value is the upload certificate's SHA-256, which you can get from either:

- Play Console → *Test and release → App integrity → Upload key certificate*
- `keytool -list -v -keystore upload-keystore.jks -alias upload`

Colons and letter case don't matter.

## 2. What CI does

`.github/scripts/android_signing.sh` is shared by `build.yml` (every `main` push and app PR) and `release.yml` (tags and dry runs).

| Step | `build.yml` | `release.yml` |
|---|---|---|
| `configure`: decode the keystore, check that the store password, alias and key password open the key, write `android/key.properties` (mode 600) | when secrets exist | when secrets exist |
| Build per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) + AAB | ✓ | ✓ |
| `cleanup`: delete the keystore and `key.properties`, even when the build fails | ✓ | ✓ |
| `verify`: `apksigner verify` every APK, `jarsigner -verify` the AAB, require one signer and the **same certificate across every artifact**, print its SHA-256 to the job summary | ✓ | ✓ |
| `bundletool validate` on the AAB (bundletool 1.18.3, SHA-256-pinned download) | ✓ | ✓ |
| Refuse debug-signed artifacts and a mismatch with `ANDROID_SIGNING_CERT_SHA256` | — | when publishing |

When publishing (a tag push, or a non-dry `workflow_dispatch` on a tag), `release.yml` **fails without the keystore secrets** instead of shipping debug-signed builds. Play rejects debug-signed bundles. Each CI runner also generates its own debug key, so a debug-signed APK could never be installed as an update over the previous one. Dry runs still fall back to debug signing, so forks can rehearse the pipeline.

Release assets carry the version in their names, like the desktop packages:

```
soundwave-<ver>-android-arm64-v8a.apk
soundwave-<ver>-android-armeabi-v7a.apk
soundwave-<ver>-android-x86_64.apk
soundwave-<ver>-android.aab
```

`deploy-android` uploads the AAB to the **internal** track automatically, but only when `GOOGLE_PLAY_SERVICE_ACCOUNT` is set.

## 3. Manual upload to the internal track

Use this for the first upload: the Play API cannot create an app, so the first release must be uploaded by hand. Also use it whenever the service account is not configured.

1. Rehearse: `gh workflow run release.yml --ref main -f dry_run=true`. Then check the `android-release` artifact and the *Android signing* block in the `build-android` job summary.
2. Tag the release (`git tag -a v1.0.0 -m "Soundwave v1.0.0" && git push origin v1.0.0`) and wait for `release.yml` to finish.
3. Download `soundwave-<ver>-android.aab` from the draft GitHub Release (or from the run's `android-release` artifact). Check it against `SHA256SUMS`:
   ```bash
   sha256sum -c --ignore-missing SHA256SUMS
   ```
4. Confirm the signer is the upload key before uploading:
   ```bash
   keytool -printcert -jarfile soundwave-<ver>-android.aab | grep -E 'Owner|SHA256'
   ```
   The SHA-256 must match the Play Console *Upload key certificate*.
5. Play Console → **Soundwave** → *Test and release → Testing → Internal testing → Create new release*.
6. Upload the AAB, set the release name to `<ver>`, and paste the release notes from `CHANGELOG.md`.
7. *Next* → resolve any warnings → *Save and publish*. Add testers on the *Testers* tab and share the opt-in link.
8. Install from the opt-in link on a physical device. Send and receive a message in CSS and in OFDM mode before you promote the release to closed testing.

## 4. Checking an APK locally

```bash
"$ANDROID_HOME"/build-tools/<version>/apksigner verify --print-certs soundwave-<ver>-android-arm64-v8a.apk
adb install soundwave-<ver>-android-arm64-v8a.apk
```

Run the helper's own tests (needs only a JDK and `zip`) with:

```bash
bash .github/scripts/test_android_signing.sh
```
