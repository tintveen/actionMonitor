#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="actionMonitor.app"
APP_DIR="/Applications/${APP_NAME}"
LEGACY_APP_DIR="${HOME}/Applications/${APP_NAME}"

echo "Installing ${APP_NAME} to ${APP_DIR}..."
if [[ -d "${LEGACY_APP_DIR}" && "${LEGACY_APP_DIR}" != "${APP_DIR}" ]]; then
  rm -rf "${LEGACY_APP_DIR}"
fi

rm -rf "${APP_DIR}"
"${ROOT_DIR}/scripts/build-app.sh" "${APP_DIR}" >/dev/null

echo "Launch with: open \"${APP_DIR}\""
open "${APP_DIR}"
