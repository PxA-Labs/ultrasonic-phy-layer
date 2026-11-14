#!/usr/bin/env bash
# Android release signing helper shared by build.yml and release.yml (#94, #35).
#
#   android_signing.sh configure <app_dir>
#       Decode ANDROID_KEYSTORE_BASE64 into <app_dir>/android/app/upload-keystore.jks,
#       check that the store password, alias and key password actually open the
#       key (so a bad secret fails here, not deep inside Gradle), and write
#       <app_dir>/android/key.properties for android/app/build.gradle.kts.
#
#   android_signing.sh verify [--apk-dir DIR] [--aab FILE] [--bundletool JAR]
#                             [--require-release-key]
#       Verify every APK (apksigner) and the AAB (jarsigner), require that all of
#       them carry the same signing certificate, and print its SHA-256 so it can
#       be matched against the Play Console upload key. With
#       --require-release-key, an Android debug certificate is an error, and so
#       is a mismatch with EXPECTED_SIGNING_CERT_SHA256 when that is set.
#       With --bundletool, the AAB is also checked by `bundletool validate`.
#
#   android_signing.sh cleanup <app_dir>
#       Remove the decoded keystore and key.properties.
#
# Secrets are passed to keytool via `:env` so they never appear in argv.
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }
note() { echo "::notice::$*"; }

# Lower-case hex with no separators, e.g. "ab:CD:01" -> "abcd01".
normalize_fp() { tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]'; }
# Same, per line (for lists of fingerprints).
normalize_lines() { tr -d ': \t' | tr '[:upper:]' '[:lower:]'; }

cmd_configure() {
  local app_dir="${1:-}"
  [ -n "$app_dir" ] || die "usage: $0 configure <app_dir>"
  [ -d "$app_dir/android/app" ] || die "$app_dir/android/app not found"
  local v
  for v in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    [ -n "${!v:-}" ] || die "$v is empty; all four ANDROID_KEYSTORE_* secrets are required for release signing"
  done

  local ks="$app_dir/android/app/upload-keystore.jks"
  local props="$app_dir/android/key.properties"
  (
    umask 077
    printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$ks" \
      || die "ANDROID_KEYSTORE_BASE64 is not valid base64"
  )
  [ -s "$ks" ] || die "decoded keystore is empty"

  # Opens the store and the key entry: a wrong store password, alias or key
  # password fails here with a clear message.
  if ! keytool -list -keystore "$ks" -storepass:env ANDROID_KEYSTORE_PASSWORD \
      -alias "$ANDROID_KEY_ALIAS" > /dev/null 2>&1; then
    rm -f "$ks"
    die "keystore cannot be opened with ANDROID_KEYSTORE_PASSWORD, or alias '$ANDROID_KEY_ALIAS' does not exist"
  fi
  local probe_dir probe_out
  probe_dir="$(mktemp -d)"
  if ! keytool -certreq -keystore "$ks" -storepass:env ANDROID_KEYSTORE_PASSWORD \
      -alias "$ANDROID_KEY_ALIAS" -keypass:env ANDROID_KEY_PASSWORD \
      -file "$probe_dir/probe.csr" > "$probe_dir/out" 2>&1; then
    probe_out="$(cat "$probe_dir/out")"
    rm -rf "$probe_dir" "$ks"
    die "ANDROID_KEY_PASSWORD does not unlock key '$ANDROID_KEY_ALIAS' (${probe_out})"
  fi
  rm -rf "$probe_dir"

  (
    umask 077
    {
      echo "storePassword=$ANDROID_KEYSTORE_PASSWORD"
      echo "keyPassword=$ANDROID_KEY_PASSWORD"
      echo "keyAlias=$ANDROID_KEY_ALIAS"
      echo "storeFile=upload-keystore.jks"
    } > "$props"
  )
  echo "Release signing configured (alias '$ANDROID_KEY_ALIAS')."
}

cmd_cleanup() {
  local app_dir="${1:-}"
  [ -n "$app_dir" ] || die "usage: $0 cleanup <app_dir>"
  rm -f "$app_dir/android/app/upload-keystore.jks" "$app_dir/android/key.properties"
  echo "Removed keystore and key.properties."
}

# Values of "<signer prefix> <field>: value" lines in apksigner output.
signer_field() { # output field
  # No match is not an error here; callers check for an empty result.
  { printf '%s\n' "$1" | grep -E "^(V[0-9.]+ )?Signer.*$2: " || true; } | sed -E "s/^.*$2: *//"
}

find_apksigner() {
  if [ -n "${APKSIGNER:-}" ]; then echo "$APKSIGNER"; return; fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [ -n "$sdk" ] || return 1
  local bt
  bt="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
  [ -n "$bt" ] && [ -x "$bt/apksigner" ] || return 1
  echo "$bt/apksigner"
}

cmd_verify() {
  local apk_dir="" aab="" bundletool="" require_release=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --apk-dir) apk_dir="${2:?}"; shift 2 ;;
      --aab) aab="${2:?}"; shift 2 ;;
      --bundletool) bundletool="${2:?}"; shift 2 ;;
      --require-release-key) require_release=true; shift ;;
      *) die "unknown verify option: $1" ;;
    esac
  done
  [ -n "$apk_dir" ] || [ -n "$aab" ] || die "verify needs --apk-dir and/or --aab"

  # name -> certificate SHA-256 (one line per artifact) and subject DN.
  local fps="" dns="" fp dn out

  if [ -n "$apk_dir" ]; then
    local apksigner apks=()
    apksigner="$(find_apksigner)" || die "apksigner not found (set ANDROID_HOME or APKSIGNER)"
    shopt -s nullglob
    apks=("$apk_dir"/*.apk)
    shopt -u nullglob
    [ ${#apks[@]} -gt 0 ] || die "no APKs in $apk_dir"
    local apk
    for apk in "${apks[@]}"; do
      echo "== $apk"
      # The exit status is the verification result.
      out="$("$apksigner" verify --verbose --print-certs "$apk")" || die "apksigner rejected $apk"
      echo "$out" | grep -E '^Verified using .*: true' || true
      # Signer lines vary by build-tools version and scheme ("Signer #1
      # certificate DN: ...", "V2 Signer: certificate DN: ...", "Signer
      # (minSdkVersion=...) certificate ..."), and several schemes or key
      # rotation can list one certificate more than once, so match any
      # signer line and require exactly one distinct digest.
      local digests
      digests="$(signer_field "$out" 'certificate SHA-256 digest' | normalize_lines | sort -u)"
      if [ -z "$digests" ]; then
        echo "$out" >&2
        die "could not read the signing certificate of $apk"
      fi
      if [ "$(echo "$digests" | wc -l | tr -d ' ')" -ne 1 ]; then
        echo "$out" | grep -E '^Signer' >&2 || true
        die "$apk must be signed by exactly one certificate"
      fi
      fp="$digests"
      dn="$(signer_field "$out" 'certificate DN' | head -1)"
      echo "Signer: $dn"
      fps+="$(basename "$apk") $fp"$'\n'
      dns+="$dn"$'\n'
    done
  fi

  if [ -n "$aab" ]; then
    [ -f "$aab" ] || die "AAB not found: $aab"
    echo "== $aab"
    out="$(jarsigner -verify "$aab" 2>&1)" || die "jarsigner rejected $aab: $out"
    echo "$out" | tail -2
    grep -q 'jar verified' <<<"$out" || die "jarsigner did not verify $aab"
    out="$(keytool -printcert -jarfile "$aab")"
    [ "$(echo "$out" | grep -c '^Signer #')" -le 1 ] || die "$aab must have exactly one signer"
    # keytool prints the leaf certificate first.
    fp="$(echo "$out" | sed -n 's/^[[:space:]]*SHA256: *//p' | head -1 | normalize_fp)"
    dn="$(echo "$out" | sed -n 's/^Owner: *//p' | head -1)"
    [ -n "$fp" ] || die "could not read the signing certificate of $aab"
    fps+="$(basename "$aab") $fp"$'\n'
    dns+="$dn"$'\n'

    if [ -n "$bundletool" ]; then
      [ -f "$bundletool" ] || die "bundletool jar not found: $bundletool"
      java -jar "$bundletool" validate --bundle="$aab" > /dev/null \
        || die "bundletool validate rejected $aab"
      echo "bundletool validate: OK"
    fi
  fi

  local unique
  unique="$(printf '%s' "$fps" | awk 'NF { print $2 }' | sort -u)"
  if [ "$(echo "$unique" | wc -l | tr -d ' ')" -ne 1 ]; then
    printf '%s' "$fps" >&2
    die "artifacts are signed with different certificates"
  fi
  local signer_dn
  signer_dn="$(printf '%s' "$dns" | awk 'NF' | head -1)"
  echo "Signing certificate: $signer_dn"
  echo "Signing certificate SHA-256: $unique"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Android signing"
      echo "- Certificate: \`$signer_dn\`"
      echo "- SHA-256: \`$unique\`"
    } >> "$GITHUB_STEP_SUMMARY"
  fi

  # The Android SDK's debug keystore always uses this subject.
  local is_debug=false
  case "$signer_dn" in *"CN=Android Debug"*) is_debug=true ;; esac

  if $require_release; then
    $is_debug && die "artifacts are debug-signed; refusing to publish (configure the ANDROID_KEYSTORE_* secrets)"
    if [ -n "${EXPECTED_SIGNING_CERT_SHA256:-}" ]; then
      local want
      want="$(printf '%s' "$EXPECTED_SIGNING_CERT_SHA256" | normalize_fp)"
      [ "$want" = "$unique" ] || die "signing certificate $unique does not match EXPECTED_SIGNING_CERT_SHA256 ($want)"
      echo "Signing certificate matches EXPECTED_SIGNING_CERT_SHA256."
    fi
  elif $is_debug; then
    note "Android artifacts are debug-signed (not for Play Store upload)."
  fi
}

case "${1:-}" in
  configure) shift; cmd_configure "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *) die "usage: $0 {configure <app_dir>|verify [options]|cleanup <app_dir>}" ;;
esac
