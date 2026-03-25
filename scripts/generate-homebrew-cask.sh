#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:?version is required}"
SHA256="${2:?sha256 is required}"
URL="${3:?url is required}"
OUTPUT_PATH="${4:-}"

read -r -d '' CASK_CONTENT <<EOF || true
cask "actionmonitor" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${URL}"
  name "actionMonitor"
  desc "Menu bar app for monitoring GitHub Actions workflows on macOS"
  homepage "https://github.com/tintveen/actionMonitor"

  depends_on macos: ">= :sonoma"

  app "actionMonitor.app"

  caveats <<~EOS
    actionMonitor is currently distributed as an unsigned app.
    If macOS blocks launch, open System Settings > Privacy & Security and allow the app to run,
    or remove quarantine for the installed app with:
      xattr -d com.apple.quarantine "/Applications/actionMonitor.app"
  EOS
end
EOF

if [[ -n "${OUTPUT_PATH}" ]]; then
  printf '%s\n' "${CASK_CONTENT}" > "${OUTPUT_PATH}"
else
  printf '%s\n' "${CASK_CONTENT}"
fi
