#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building libsoundwave in ${NATIVE_DIR}..."
cd "${NATIVE_DIR}"

cmake --preset release
cmake --build build/release --parallel
ctest --test-dir build/release -C Release --output-on-failure

echo "==> Soundwave build and tests completed successfully!"
