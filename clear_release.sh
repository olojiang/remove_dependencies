#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "$0")" && pwd)/release"
mkdir -p "${RELEASE_DIR}"
find "${RELEASE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
echo "Cleared ${RELEASE_DIR}"
