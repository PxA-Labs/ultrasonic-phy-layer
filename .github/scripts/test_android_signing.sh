#!/usr/bin/env bash
# Self-test for android_signing.sh (#94). Needs only a JDK (keytool,
# jarsigner) and zip; the APK path needs apksigner and is exercised in
# build.yml/release.yml on real builds.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/android_signing.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
expect_ok() { local name="$1"; shift; if "$@" > "$work/log" 2>&1; then ok "$name"; else bad "$name"; cat "$work/log"; fi; }
expect_fail() { # name, expected-message-regex, cmd...
  local name="$1" re="$2"; shift 2
  if "$@" > "$work/log" 2>&1; then bad "$name (unexpectedly succeeded)"; cat "$work/log"
  elif grep -Eq "$re" "$work/log"; then ok "$name"
  else bad "$name (wrong error)"; cat "$work/log"; fi
}

# JKS so that the key password can differ from the store password.
mkkey() { # file alias dname storepass keypass
  keytool -genkeypair -storetype JKS -keystore "$1" -alias "$2" -dname "$3" \
    -storepass "$4" -keypass "$5" -keyalg RSA -keysize 2048 -validity 2 > /dev/null 2>&1
}
mkkey release.jks upload "CN=Soundwave Upload, O=PxA Labs" store-secret key-secret
mkkey debug.jks androiddebugkey "CN=Android Debug, O=Android, C=US" android android
mkkey other.jks upload "CN=Someone Else" store-secret key-secret

mkdir -p payload/base/manifest
echo "<manifest/>" > payload/base/manifest/AndroidManifest.xml
(cd payload && zip -qr ../unsigned.aab .)
sign() { # in out keystore storepass keypass alias
  cp "$1" "$2"
  jarsigner -keystore "$3" -storepass "$4" -keypass "$5" "$2" "$6" > /dev/null 2>&1
}
sign unsigned.aab release.aab release.jks store-secret key-secret upload
sign unsigned.aab debug.aab debug.jks android android androiddebugkey
sign unsigned.aab other.aab other.jks store-secret key-secret upload

fp_of() { keytool -printcert -jarfile "$1" | sed -n 's/^[[:space:]]*SHA256: *//p' | head -1 | tr -d ':' | tr '[:upper:]' '[:lower:]'; }
release_fp="$(fp_of release.aab)"

# ---- configure -----------------------------------------------------------
mkdir -p app/android/app
b64="$(base64 < release.jks | tr -d '\n')"
run_configure() { # storepass alias keypass [b64]
  env ANDROID_KEYSTORE_BASE64="${4-$b64}" ANDROID_KEYSTORE_PASSWORD="$1" \
    ANDROID_KEY_ALIAS="$2" ANDROID_KEY_PASSWORD="$3" "$tool" configure app
}
expect_ok "configure with valid secrets" run_configure store-secret upload key-secret
if grep -qx 'keyAlias=upload' app/android/key.properties \
    && grep -qx 'storeFile=upload-keystore.jks' app/android/key.properties \
    && cmp -s release.jks app/android/app/upload-keystore.jks; then
  ok "key.properties and keystore written"
else bad "key.properties and keystore written"; fi
perms="$(stat -c '%a' app/android/key.properties 2>/dev/null || stat -f '%Lp' app/android/key.properties)"
check "key.properties is owner-only (mode $perms)" [ "$perms" = "600" ]

expect_fail "wrong store password" "cannot be opened" run_configure wrong-pass upload key-secret
check "keystore removed after failure" [ ! -e app/android/app/upload-keystore.jks ]
expect_fail "unknown alias" "does not exist" run_configure store-secret missing key-secret
expect_fail "wrong key password" "does not unlock" run_configure store-secret upload wrong-pass
expect_fail "missing secret" "ANDROID_KEY_PASSWORD is empty" run_configure store-secret upload ""
expect_fail "empty keystore" "empty" run_configure store-secret upload key-secret ""

expect_ok "cleanup" "$tool" cleanup app
check "cleanup removed secrets" test ! -e app/android/key.properties -a ! -e app/android/app/upload-keystore.jks

# ---- verify --------------------------------------------------------------
expect_ok "release-signed AAB verifies" "$tool" verify --aab release.aab
check "prints certificate SHA-256" grep -q "SHA-256: $release_fp" "$work/log"
expect_ok "release key accepted for publishing" "$tool" verify --aab release.aab --require-release-key
expect_ok "debug-signed AAB allowed for dry runs" "$tool" verify --aab debug.aab
check "debug signing is reported" grep -q "debug-signed" "$work/log"
expect_fail "debug key refused for publishing" "refusing to publish" "$tool" verify --aab debug.aab --require-release-key
expect_fail "unsigned AAB rejected" "jarsigner|exactly one|could not read" "$tool" verify --aab unsigned.aab

colon_fp="$(echo "$release_fp" | tr '[:lower:]' '[:upper:]' | sed 's/../&:/g; s/:$//')"
expect_ok "pinned certificate matches (colon/upper-case form)" \
  env EXPECTED_SIGNING_CERT_SHA256="$colon_fp" "$tool" verify --aab release.aab --require-release-key
expect_fail "pinned certificate mismatch" "does not match" \
  env EXPECTED_SIGNING_CERT_SHA256="$release_fp" "$tool" verify --aab other.aab --require-release-key

# Tamper with a signed entry: the signature must no longer verify.
cp release.aab tampered.aab
mkdir -p tamper/base/manifest && echo "<manifest evil='1'/>" > tamper/base/manifest/AndroidManifest.xml
(cd tamper && zip -q ../tampered.aab base/manifest/AndroidManifest.xml)
expect_fail "tampered AAB rejected" "jarsigner" "$tool" verify --aab tampered.aab

expect_fail "missing AAB rejected" "not found" "$tool" verify --aab nope.aab
expect_fail "verify needs an input" "needs --apk-dir" "$tool" verify
expect_fail "APK check without apksigner fails closed" "apksigner not found" \
  env -u ANDROID_HOME -u ANDROID_SDK_ROOT -u APKSIGNER "$tool" verify --apk-dir .

# ---- APK path (stub apksigner replaying real output formats) -------------
mkdir -p apks
touch apks/app-arm64-v8a-release.apk apks/app-x86_64-release.apk
cat > stub-apksigner <<'STUB'
#!/usr/bin/env bash
cat "$STUB_OUT"
exit "${STUB_RC:-0}"
STUB
chmod +x stub-apksigner
other_fp="$(fp_of other.aab)"
debug_fp="$(fp_of debug.aab)"
fmt_numbered() { # fp dn
  printf 'Verifies\nVerified using v1 scheme (JAR signing): false\nVerified using v2 scheme (APK Signature Scheme v2): true\nNumber of signers: 1\nSigner #1 certificate DN: %s\nSigner #1 certificate SHA-256 digest: %s\nSigner #1 certificate SHA-1 digest: 00\n' "$2" "$1"
}
fmt_minsdk() { # fp dn  (v3.1 / rotation style; one cert listed twice)
  printf 'Verifies\nVerified using v3.1 scheme (APK Signature Scheme v3.1): true\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate DN: %s\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s\nSigner (minSdkVersion=24, maxSdkVersion=32) certificate DN: %s\nSigner (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: %s\n' "$2" "$1" "$2" "$1"
}
fmt_scheme() { # fp dn  (build-tools 34+ on ubuntu-latest, captured from CI)
  printf 'Verifies\nVerified using v1 scheme (JAR signing): false\nVerified using v2 scheme (APK Signature Scheme v2): true\nVerified using v3 scheme (APK Signature Scheme v3): false\nVerified for SourceStamp: false\nV2 Signer: certificate DN: %s\nV2 Signer: certificate SHA-256 digest: %s\nV2 Signer: certificate SHA-1 digest: 3265eae27468695f2e467f91a02d99bd9661e1ce\nV2 Signer: key algorithm: RSA\nV2 Signer: public key SHA-256 digest: 2569e7a0ed0b3e1324c8e6210d078610616d79006d5935c3a0aaefac7c7c1d38\n' "$2" "$1"
}
apk_verify() { env APKSIGNER="$work/stub-apksigner" STUB_OUT="$work/stub.out" "$tool" verify --apk-dir apks "$@"; }

fmt_numbered "$release_fp" "CN=Soundwave Upload, O=PxA Labs" > stub.out
expect_ok "APKs: 'Signer #1' output format" apk_verify
check "APKs: signer DN is printed" grep -q "Signer: CN=Soundwave Upload" "$work/log"
expect_ok "APKs and AAB with the same certificate" apk_verify --aab release.aab --require-release-key
expect_fail "APKs and AAB with different certificates" "different certificates" apk_verify --aab other.aab

fmt_scheme "$release_fp" "CN=Soundwave Upload, O=PxA Labs" > stub.out
expect_ok "APKs: 'V2 Signer:' format (public key digest ignored)" apk_verify --aab release.aab
{ fmt_scheme "$release_fp" "CN=Soundwave Upload"; printf 'V3 Signer: certificate DN: CN=Soundwave Upload\nV3 Signer: certificate SHA-256 digest: %s\n' "$release_fp"; } > stub.out
expect_ok "APKs: same certificate under V2 and V3 schemes" apk_verify --aab release.aab
fmt_scheme "$debug_fp" "C=US, O=Android, CN=Android Debug" > stub.out
expect_fail "APKs: debug certificate (C=US, O=Android, CN=...) refused" "refusing to publish" apk_verify --require-release-key

fmt_minsdk "$release_fp" "CN=Soundwave Upload, O=PxA Labs" > stub.out
expect_ok "APKs: '(minSdkVersion=...)' format with a repeated certificate" apk_verify --aab release.aab

{ fmt_numbered "$release_fp" "CN=Soundwave Upload"; printf 'Signer #2 certificate DN: CN=Someone Else\nSigner #2 certificate SHA-256 digest: %s\n' "$other_fp"; } > stub.out
expect_fail "APKs: two signing certificates rejected" "exactly one certificate" apk_verify

printf 'Verifies\nVerified using v2 scheme (APK Signature Scheme v2): true\n' > stub.out
expect_fail "APKs: unreadable certificate fails closed" "could not read the signing certificate" apk_verify

fmt_numbered "$debug_fp" "CN=Android Debug, O=Android, C=US" > stub.out
expect_fail "APKs: debug certificate refused for publishing" "refusing to publish" apk_verify --require-release-key

echo "DOES NOT VERIFY" > stub.out
expect_fail "APKs: apksigner rejection propagates" "apksigner rejected" env STUB_RC=1 APKSIGNER="$work/stub-apksigner" STUB_OUT="$work/stub.out" "$tool" verify --apk-dir apks

mkdir -p empty-apks
expect_fail "APKs: empty directory rejected" "no APKs" env APKSIGNER="$work/stub-apksigner" "$tool" verify --apk-dir empty-apks

echo "android_signing self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
