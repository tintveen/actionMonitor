#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="actionMonitor.app"
APP_DIR="/Applications/${APP_NAME}"
LEGACY_APP_DIR="${HOME}/Applications/${APP_NAME}"
STAGING_DIR="$(mktemp -d)"
STAGED_APP_DIR="${STAGING_DIR}/${APP_NAME}"

cleanup() {
  rm -rf "${STAGING_DIR}"
}

trap cleanup EXIT

echo "Installing ${APP_NAME} to ${APP_DIR}..."
if [[ -d "${LEGACY_APP_DIR}" && "${LEGACY_APP_DIR}" != "${APP_DIR}" ]]; then
  rm -rf "${LEGACY_APP_DIR}"
fi

ACTIONMONITOR_INCLUDE_LOCAL_OAUTH_CONFIG=1 \
  "${ROOT_DIR}/scripts/build-app.sh" "${STAGED_APP_DIR}" >/dev/null

rm -rf "${APP_DIR}"
mv "${STAGED_APP_DIR}" "${APP_DIR}"

echo "Launch with: open \"${APP_DIR}\""
open "${APP_DIR}"
