#!/usr/bin/env bash
# Build libsoundwave (universal arm64+x86_64) and embed it in a built
# soundwave.app at Contents/Frameworks/libsoundwave.dylib, where
# lib/native/soundwave_native.dart looks for it
# (<exe dir>/../Frameworks/libsoundwave.dylib; the Runner's
# LD_RUNPATH_SEARCH_PATHS also contains @executable_path/../Frameworks).
#
# Usage: embed_native.sh <path/to/soundwave.app>
# Run from anywhere; paths are resolved relative to the repository root.
set -euo pipefail

APP="${1:?usage: embed_native.sh <path/to/soundwave.app>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NATIVE_BUILD="${REPO_ROOT}/native/build-macos-app"

cmake -S "${REPO_ROOT}/native" -B "${NATIVE_BUILD}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DSW_BUILD_TESTS=OFF -DSW_BUILD_BENCHMARKS=OFF -DSW_FUZZ_SMOKE=OFF
cmake --build "${NATIVE_BUILD}" --config Release --target soundwave_shared \
  -j "$(sysctl -n hw.ncpu)"

DEST="${APP}/Contents/Frameworks/libsoundwave.dylib"
mkdir -p "${APP}/Contents/Frameworks"
# libsoundwave.dylib is a symlink to the versioned file; copy the real file.
cp -fL "${NATIVE_BUILD}/libsoundwave.dylib" "${DEST}"
chmod 755 "${DEST}"
install_name_tool -id "@rpath/libsoundwave.dylib" "${DEST}"

echo "Embedded ${DEST}:"
lipo -info "${DEST}"
otool -L "${DEST}"
