#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="actionMonitor.app"
APP_DIR="${HOME}/Applications/${APP_NAME}"
LAUNCHER_PATH="/opt/homebrew/bin/actionMonitor"

cd "${ROOT_DIR}"

echo "Building actionMonitor (release)..."
swift build -c release >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/actionMonitor"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Expected executable not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "Installing ${APP_NAME} to ${APP_DIR}..."
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "${ROOT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/actionMonitor"

echo "Installing terminal launcher to ${LAUNCHER_PATH}..."
mkdir -p "$(dirname "${LAUNCHER_PATH}")"
cat > "${LAUNCHER_PATH}" <<EOF
#!/usr/bin/env bash
open "${APP_DIR}"
EOF
chmod +x "${LAUNCHER_PATH}"

echo "Launch with: open \"${APP_DIR}\""
echo "Terminal shortcut: actionMonitor"
open "${APP_DIR}"
