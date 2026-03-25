#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

if command -v gitleaks >/dev/null 2>&1; then
  exec gitleaks git --redact "${ROOT_DIR}"
fi

if command -v docker >/dev/null 2>&1; then
  exec docker run --rm -v "${ROOT_DIR}:/repo" zricethezav/gitleaks:v8.24.2 git --redact /repo
fi

echo "gitleaks is not installed and Docker is unavailable. Install gitleaks or run this script in CI." >&2
exit 1
