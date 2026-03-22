#!/usr/bin/env bash

set -euo pipefail

APP_DIR="${HOME}/Applications/DeployBar.app"
LAUNCHER_PATH="/opt/homebrew/bin/deploybar"

if [[ -d "${APP_DIR}" ]]; then
  echo "Removing ${APP_DIR}..."
  rm -rf "${APP_DIR}"
else
  echo "App bundle not found at ${APP_DIR}"
fi

if [[ -L "${LAUNCHER_PATH}" || -f "${LAUNCHER_PATH}" ]]; then
  echo "Removing launcher ${LAUNCHER_PATH}..."
  rm -f "${LAUNCHER_PATH}"
else
  echo "Launcher not found at ${LAUNCHER_PATH}"
fi
