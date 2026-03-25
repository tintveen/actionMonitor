#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${1:-${ROOT_DIR}/dist}"

if [[ "${DIST_DIR}" != /* ]]; then
  DIST_DIR="${ROOT_DIR}/${DIST_DIR}"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Support/Info.plist")"
APP_PATH="${DIST_DIR}/actionMonitor.app"
ARCHIVE_NAME="actionMonitor-${VERSION}-macos.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
REPOSITORY_SLUG="${GITHUB_REPOSITORY:-tintveen/actionMonitor}"
RELEASE_URL="https://github.com/${REPOSITORY_SLUG}/releases/download/v${VERSION}/${ARCHIVE_NAME}"

mkdir -p "${DIST_DIR}"
ACTIONMONITOR_INCLUDE_LOCAL_OAUTH_CONFIG=0 \
  "${ROOT_DIR}/scripts/build-app.sh" "${APP_PATH}" >/dev/null

rm -f "${ARCHIVE_PATH}"
(
  cd "${DIST_DIR}"
  COPYFILE_DISABLE=1 zip -qryX "${ARCHIVE_PATH}" "$(basename "${APP_PATH}")"
)

SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
CASK_PATH="${DIST_DIR}/actionmonitor.rb"
MANIFEST_PATH="${DIST_DIR}/release-metadata.txt"

"${ROOT_DIR}/scripts/generate-homebrew-cask.sh" "${VERSION}" "${SHA256}" "${RELEASE_URL}" "${CASK_PATH}" >/dev/null

cat > "${MANIFEST_PATH}" <<EOF
version=${VERSION}
archive=${ARCHIVE_PATH}
sha256=${SHA256}
release_url=${RELEASE_URL}
cask=${CASK_PATH}
EOF

echo "Created archive: ${ARCHIVE_PATH}"
echo "SHA-256: ${SHA256}"
echo "Release URL: ${RELEASE_URL}"
echo "Cask: ${CASK_PATH}"
echo "Metadata: ${MANIFEST_PATH}"
