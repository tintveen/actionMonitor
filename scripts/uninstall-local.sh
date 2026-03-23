#!/usr/bin/env bash

set -euo pipefail

APP_DIR="${HOME}/Applications/actionMonitor.app"

if [[ -d "${APP_DIR}" ]]; then
  echo "Removing ${APP_DIR}..."
  rm -rf "${APP_DIR}"
else
  echo "App bundle not found at ${APP_DIR}"
fi
