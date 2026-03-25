#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="actionMonitor.app"
APP_DIR="/Applications/${APP_NAME}"
LEGACY_APP_DIR="${HOME}/Applications/${APP_NAME}"
ICON_SRC="${ROOT_DIR}/docs/actionMonitor-icon.svg"
ICON_NAME="actionMonitor"

cd "${ROOT_DIR}"

WORK_DIR="$(mktemp -d)"
ICONSET_DIR="${WORK_DIR}/${ICON_NAME}.iconset"
APP_ICON_PATH="${APP_DIR}/Contents/Resources/${ICON_NAME}.icns"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

generate_icon() {
  mkdir -p "${ICONSET_DIR}"

  local sizes=(16 32 128 256 512)

  for size in "${sizes[@]}"; do
    local doubled_size=$((size * 2))

    sips -s format png -z "${size}" "${size}" "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null 2>/dev/null
    sips -s format png -z "${doubled_size}" "${doubled_size}" "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null 2>/dev/null
  done

  iconutil -c icns "${ICONSET_DIR}" -o "${APP_ICON_PATH}" >/dev/null
}

echo "Building actionMonitor (release)..."
swift build -c release >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/actionMonitor"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Expected executable not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "Installing ${APP_NAME} to ${APP_DIR}..."
if [[ -d "${LEGACY_APP_DIR}" && "${LEGACY_APP_DIR}" != "${APP_DIR}" ]]; then
  rm -rf "${LEGACY_APP_DIR}"
fi

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${ROOT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/actionMonitor"
generate_icon

echo "Launch with: open \"${APP_DIR}\""
open "${APP_DIR}"
