#!/usr/bin/env bash
# Sign soundwave.app (Developer ID when a certificate is available, ad-hoc
# otherwise), wrap it in a DMG and, when credentials are present, notarize and
# staple it.
#
# Usage: sign_and_package.sh <path/to/soundwave.app> <output.dmg>
#
# Optional environment (all set by the release workflow from secrets):
#   MACOS_SIGNING_IDENTITY   codesign identity ("Developer ID Application: ...").
#                            Empty => ad-hoc signature ("-").
#   MACOS_KEYCHAIN           keychain holding the identity.
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#                            notarytool credentials. All three required to
#                            notarize; skipped otherwise.
set -euo pipefail

APP="${1:?usage: sign_and_package.sh <app> <dmg>}"
DMG="${2:?usage: sign_and_package.sh <app> <dmg>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="${HERE}/../Runner/Release.entitlements"
IDENTITY="${MACOS_SIGNING_IDENTITY:-}"

sign_args=(--force --options runtime)
if [[ -n "${IDENTITY}" ]]; then
  echo "Signing with Developer ID identity"
  sign_args+=(--timestamp --sign "${IDENTITY}")
  [[ -n "${MACOS_KEYCHAIN:-}" ]] && sign_args+=(--keychain "${MACOS_KEYCHAIN}")
else
  echo "::notice::No macOS signing identity; using an ad-hoc signature (not notarizable)."
  sign_args+=(--sign -)
fi

# Nested code first (frameworks, dylibs incl. libsoundwave), then the app
# itself with the sandbox + microphone entitlements.
while IFS= read -r -d '' item; do
  codesign "${sign_args[@]}" "${item}"
done < <(find "${APP}/Contents/Frameworks" -maxdepth 1 \
           \( -name '*.dylib' -o -name '*.framework' \) -print0)
codesign "${sign_args[@]}" --entitlements "${ENTITLEMENTS}" "${APP}"

codesign --verify --deep --strict --verbose=2 "${APP}"
echo "Entitlements:"
ENT_DUMP="$(mktemp)"
codesign -d --entitlements - "${APP}" 2>/dev/null | tee "${ENT_DUMP}"
grep -q "com.apple.security.device.audio-input" "${ENT_DUMP}" \
  || { echo "::error::audio-input entitlement missing"; exit 1; }

STAGING="$(mktemp -d)"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
rm -f "${DMG}"
hdiutil create -volname "Soundwave" -srcfolder "${STAGING}" -ov \
  -format UDZO "${DMG}"
rm -rf "${STAGING}"

if [[ -n "${IDENTITY}" ]]; then
  dmg_args=(--force --timestamp --sign "${IDENTITY}")
  [[ -n "${MACOS_KEYCHAIN:-}" ]] && dmg_args+=(--keychain "${MACOS_KEYCHAIN}")
  codesign "${dmg_args[@]}" "${DMG}"
fi

if [[ -n "${IDENTITY}" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" \
      && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Notarizing ${DMG}"
  xcrun notarytool submit "${DMG}" --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" --password "${APPLE_APP_PASSWORD}" --wait
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
else
  echo "::notice::Notarization skipped (needs Developer ID identity + APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD)."
fi

hdiutil imageinfo "${DMG}" | head -5
ls -l "${DMG}"
