# Google Play Data Safety Form (DRAFT answers)

!!! danger "DRAFT — requires legal review before publication"
    These answers are derived from the source code. They must be reviewed and checked against the **exact build submitted**, including permissions and SDKs added by third-party plugins, before they are entered in Play Console. Answering the form incorrectly is a policy violation.

## Basis (verified in code)

| Fact | Evidence |
|---|---|
| No network code in the app | No `dart:io` `HttpClient`/`Socket`, `package:http`, `url_launcher` or other networking found in `soundwave_app/lib/` |
| No analytics, ads or crash-reporting SDKs | `soundwave_app/pubspec.yaml` dependencies: `ffi`, `path_provider`, `record`, `audioplayers`, `provider`, `shared_preferences`, `file_picker`, `share_plus`, `cupertino_icons` |
| `INTERNET` is not requested by the app's release manifest | `android/app/src/main/AndroidManifest.xml` declares only `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS`. `INTERNET` appears only in the debug and profile manifests (Flutter tooling) |
| Microphone audio is processed on the device | `RxEngine` → `libsoundwave` through FFI. Audio leaves memory only if the user records, saves a sample, or exports and shares |
| User-initiated sharing only | `share_plus` share sheet (message export), `file_picker` (user-selected files) |

**Open verification item:** inspect the merged manifest of the release AAB/APK (`aapt dump permissions` or the Play Console bundle explorer). If a plugin adds `INTERNET` or any other permission, re-evaluate the answers below.

## Section 1: Data collection and security

| Question | Draft answer | Reasoning |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | Under Play's definitions, "collect" means transmitting data off the device. Data processed only on the device, or sent off it only through a user-initiated share to an app the user chooses, is not "collected" or "shared" |
| Is all user data encrypted in transit? | Not applicable (nothing is collected) | Acoustic broadcasts are not a transfer to the developer. They are disclosed as unencrypted in the privacy policy |
| Do you provide a way for users to request that their data is deleted? | Not applicable (nothing is collected) | Users can delete local data in the app (*Clear All*) or by uninstalling |

## Section 2: Data types (for reviewers)

If reviewers decide that something counts as collected, these are the candidate categories:

| Play category | What the app does | Draft classification |
|---|---|---|
| Audio → Voice or sound recordings | Microphone input decoded in memory. WAV saved locally only on user action | Processed on device only. Not collected |
| Files and docs | User-picked files transmitted acoustically, received files saved locally | Not collected by the developer |
| Messages → Other in-app messages | Decoded text kept in memory and exported only by the user | Not collected |
| App activity, App info and performance, Device or other IDs, Location, Personal info, Financial info, Health, Contacts, Calendar, Photos/videos, Web browsing | Not accessed | — |

## Section 3: Security practices to state in the listing

- Data is not transferred off the device by the app.
- Users can delete stored recordings, exports and samples in the app.
- Transmissions over sound are not encrypted (disclose this in the description and privacy policy rather than in the form).
- Independent security review: **No** (none performed).

## Related

- [Privacy policy (draft)](../legal/PRIVACY_POLICY.md)
- [Play Store listing (draft)](PLAY_STORE_LISTING.md)
