#!/usr/bin/env bash
# Package a Flutter Linux release bundle as tar.gz, .deb and AppImage.
#
# Usage: package.sh <bundle-dir> <version> <out-dir>
#   bundle-dir  build/linux/x64/release/bundle (must contain lib/libsoundwave.so)
#   version     e.g. 1.0.0 (no leading "v")
#   out-dir     directory that receives the packages
#
# Env: APPIMAGETOOL  path to appimagetool (downloaded if unset).
set -euo pipefail

BUNDLE="$(cd "${1:?bundle dir}" && pwd)"
VERSION="${2:?version}"
OUT="${3:?out dir}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPIMAGETOOL_VERSION="1.9.1"
mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

test -x "${BUNDLE}/soundwave" || { echo "::error::soundwave binary missing in ${BUNDLE}"; exit 1; }
test -f "${BUNDLE}/lib/libsoundwave.so" || { echo "::error::lib/libsoundwave.so missing in ${BUNDLE}"; exit 1; }

# ---- tar.gz -----------------------------------------------------------------
TARBALL="${OUT}/soundwave-${VERSION}-linux-x64.tar.gz"
tar -C "$(dirname "${BUNDLE}")" --transform "s,^$(basename "${BUNDLE}"),soundwave-${VERSION}," \
  -czf "${TARBALL}" "$(basename "${BUNDLE}")"

# ---- .deb -------------------------------------------------------------------
DEBROOT="${WORK}/deb"
mkdir -p "${DEBROOT}/DEBIAN" "${DEBROOT}/opt/soundwave" "${DEBROOT}/usr/bin" \
  "${DEBROOT}/usr/share/applications" \
  "${DEBROOT}/usr/share/icons/hicolor/256x256/apps"
cp -a "${BUNDLE}/." "${DEBROOT}/opt/soundwave/"
ln -s /opt/soundwave/soundwave "${DEBROOT}/usr/bin/soundwave"
install -m 644 "${HERE}/soundwave.desktop" "${DEBROOT}/usr/share/applications/"
install -m 644 "${HERE}/soundwave.png" \
  "${DEBROOT}/usr/share/icons/hicolor/256x256/apps/soundwave.png"
INSTALLED_KB="$(du -sk "${DEBROOT}" | cut -f1)"
cat > "${DEBROOT}/DEBIAN/control" <<CONTROL
Package: soundwave
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: PxA Labs <noreply@github.com>
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0 | libgtk-3-0t64, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0
Homepage: https://github.com/PxA-Labs/ultrasonic-phy-layer
Description: Ultrasonic physical-layer data modem
 Soundwave sends and receives data over near-ultrasonic audio using the
 libsoundwave DSP core (OFDM/CSS, Reed-Solomon FEC).
CONTROL
DEB="${OUT}/soundwave_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "${DEBROOT}" "${DEB}"
dpkg-deb --info "${DEB}"
dpkg-deb --contents "${DEB}" | grep -q "./opt/soundwave/lib/libsoundwave.so" \
  || { echo "::error::libsoundwave.so missing from .deb"; exit 1; }

# ---- AppImage ---------------------------------------------------------------
APPDIR="${WORK}/Soundwave.AppDir"
mkdir -p "${APPDIR}/usr/lib/soundwave" "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
cp -a "${BUNDLE}/." "${APPDIR}/usr/lib/soundwave/"
cp "${HERE}/soundwave.desktop" "${APPDIR}/soundwave.desktop"
cp "${HERE}/soundwave.png" "${APPDIR}/soundwave.png"
cp "${HERE}/soundwave.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/soundwave.png"
cat > "${APPDIR}/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "${HERE}/usr/lib/soundwave/soundwave" "$@"
APPRUN
chmod 755 "${APPDIR}/AppRun"

if [[ -z "${APPIMAGETOOL:-}" ]]; then
  APPIMAGETOOL="${WORK}/appimagetool"
  curl -fsSL -o "${APPIMAGETOOL}" \
    "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"
  chmod +x "${APPIMAGETOOL}"
fi
APPIMAGE="${OUT}/Soundwave-${VERSION}-x86_64.AppImage"
# --appimage-extract-and-run: CI runners have no FUSE.
ARCH=x86_64 "${APPIMAGETOOL}" --appimage-extract-and-run --no-appstream \
  "${APPDIR}" "${APPIMAGE}"
chmod +x "${APPIMAGE}"
( cd "${WORK}" && "${APPIMAGE}" --appimage-extract >/dev/null \
  && test -f squashfs-root/usr/lib/soundwave/lib/libsoundwave.so ) \
  || { echo "::error::libsoundwave.so missing from AppImage"; exit 1; }

ls -l "${OUT}"
