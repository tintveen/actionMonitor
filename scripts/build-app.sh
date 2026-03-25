#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="actionMonitor.app"
EXECUTABLE_NAME="actionMonitor"
ICON_NAME="actionMonitor"
ICON_SRC="${ROOT_DIR}/docs/actionMonitor-icon.svg"
BASE_INFO_PLIST="${ROOT_DIR}/Support/Info.plist"
DEFAULT_LOCAL_INFO_PLIST="${ROOT_DIR}/Support/Info.local.plist"
BUILD_CONFIGURATION="${ACTIONMONITOR_BUILD_CONFIGURATION:-release}"
INCLUDE_DEFAULT_LOCAL_INFO_PLIST="${ACTIONMONITOR_INCLUDE_LOCAL_OAUTH_CONFIG:-0}"
OUTPUT_PATH="${1:-${ROOT_DIR}/dist/${APP_NAME}}"

if [[ "${OUTPUT_PATH}" != /* ]]; then
  OUTPUT_PATH="${ROOT_DIR}/${OUTPUT_PATH}"
fi

WORK_DIR="$(mktemp -d)"
ICONSET_DIR="${WORK_DIR}/${ICON_NAME}.iconset"
RESOLVED_INFO_PLIST="${WORK_DIR}/Info.plist"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

set_plist_value() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Delete :${key}" "${plist_path}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${plist_path}" >/dev/null
}

copy_plist_value_if_present() {
  local source_plist="$1"
  local destination_plist="$2"
  local key="$3"
  local value

  value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${source_plist}" 2>/dev/null || true)"
  if [[ -n "${value}" ]]; then
    set_plist_value "${destination_plist}" "${key}" "${value}"
  fi
}

resolve_info_plist() {
  local resolved_plist="$1"
  local explicit_local_override_plist="${ACTIONMONITOR_GITHUB_OAUTH_INFO_PLIST:-${ACTIONMONITOR_LOCAL_INFO_PLIST:-}}"
  local local_override_plist=""

  cp "${BASE_INFO_PLIST}" "${resolved_plist}"

  if [[ -n "${explicit_local_override_plist}" ]]; then
    local_override_plist="${explicit_local_override_plist}"
  elif [[ "${INCLUDE_DEFAULT_LOCAL_INFO_PLIST}" == "1" ]]; then
    local_override_plist="${DEFAULT_LOCAL_INFO_PLIST}"
  fi

  if [[ -n "${local_override_plist}" && -f "${local_override_plist}" ]]; then
    copy_plist_value_if_present "${local_override_plist}" "${resolved_plist}" "GitHubOAuthAppClientID"
    copy_plist_value_if_present "${local_override_plist}" "${resolved_plist}" "GitHubOAuthAppClientSecret"
  fi

  if [[ -n "${ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID:-}" ]]; then
    set_plist_value "${resolved_plist}" "GitHubOAuthAppClientID" "${ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID}"
  fi

  if [[ -n "${ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET:-}" ]]; then
    set_plist_value "${resolved_plist}" "GitHubOAuthAppClientSecret" "${ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET}"
  fi
}

generate_icon() {
  local icon_output_path="$1"
  mkdir -p "${ICONSET_DIR}"

  local sizes=(16 32 128 256 512)

  for size in "${sizes[@]}"; do
    local doubled_size=$((size * 2))
    sips -s format png -z "${size}" "${size}" "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null 2>/dev/null
    sips -s format png -z "${doubled_size}" "${doubled_size}" "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null 2>/dev/null
  done

  iconutil -c icns "${ICONSET_DIR}" -o "${icon_output_path}" >/dev/null
}

echo "Building actionMonitor (${BUILD_CONFIGURATION})..."
cd "${ROOT_DIR}"
swift build -c "${BUILD_CONFIGURATION}" >/dev/null
BIN_DIR="$(swift build -c "${BUILD_CONFIGURATION}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Expected executable not found at ${BIN_PATH}" >&2
  exit 1
fi

resolve_info_plist "${RESOLVED_INFO_PLIST}"

rm -rf "${OUTPUT_PATH}"
mkdir -p "${OUTPUT_PATH}/Contents/MacOS"
mkdir -p "${OUTPUT_PATH}/Contents/Resources"

cp "${RESOLVED_INFO_PLIST}" "${OUTPUT_PATH}/Contents/Info.plist"
cp "${BIN_PATH}" "${OUTPUT_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
generate_icon "${OUTPUT_PATH}/Contents/Resources/${ICON_NAME}.icns"

echo "${OUTPUT_PATH}"
