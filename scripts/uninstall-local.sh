#!/usr/bin/env bash

set -euo pipefail

APP_DIRS=(
  "/Applications/actionMonitor.app"
  "${HOME}/Applications/actionMonitor.app"
)

removed_any=false

for APP_DIR in "${APP_DIRS[@]}"; do
  if [[ -d "${APP_DIR}" ]]; then
    echo "Removing ${APP_DIR}..."
    rm -rf "${APP_DIR}"
    removed_any=true
  fi
done

if [[ "${removed_any}" == false ]]; then
  echo "App bundle not found in /Applications or ~/Applications"
fi
