#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${PROJECT_DIR}/deb_download"
mkdir -p "${DOWNLOAD_DIR}"

HTML="$(mktemp)"
trap 'rm -f "${HTML}"' EXIT
curl --fail --location --silent --show-error \
  https://www.adspower.com/download > "${HTML}"

read -r VERSION URL < <(python3 - "${HTML}" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
pattern = r'https://version\.adspower\.net/software/linux-x64-global/([0-9.]+)/AdsPower-Global-\1-x64\.deb'
m = re.search(pattern, html)
if not m:
    raise SystemExit("Could not find the latest AdsPower Linux x64 .deb URL")
print(m.group(1), m.group(0))
PY
)

DEB="${DOWNLOAD_DIR}/AdsPower-Global-${VERSION}-x64.deb"
echo "[+] Downloading AdsPower ${VERSION}"
curl --fail --location --progress-bar "${URL}" -o "${DEB}"
printf '{"version":"%s","url":"%s","deb_file":"%s"}\n' \
  "${VERSION}" "${URL}" "${DEB}" > "${PROJECT_DIR}/deb_info.json"
echo "[+] Saved ${DEB}"
