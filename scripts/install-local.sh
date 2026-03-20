#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeployBar.app"
APP_DIR="${HOME}/Applications/${APP_NAME}"

cd "${ROOT_DIR}"

echo "Building deployBar (release)..."
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/deployBar"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Expected executable not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "Installing ${APP_NAME} to ${APP_DIR}..."
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "${ROOT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/deployBar"

echo "Launch with: open \"${APP_DIR}\""
open "${APP_DIR}"
