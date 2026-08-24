#!/usr/bin/env bash
# Baidu Net Disk (baidunetdisk) management: shared constants and helpers.
#
# Upstream publishes versioned debs under a predictable CDN pattern but
# provides no version listing API. We discover the latest version by probing
# candidate versions (HEAD requests are cheap) starting from KNOWN_LATEST.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="baidunetdisk"
CDN_BASE="https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia"
KNOWN_LATEST="4.17.8"          # last version confirmed to exist (probed)
PROBE_HIGHER=5                 # how many candidate versions to try above known

deb_url() { printf '%s/%s/baidunetdisk_%s_amd64.deb\n' "$CDN_BASE" "$1" "$1"; }

version_ge() {  # version_ge A B -> true if A >= B (dpkg --compare-versions)
  dpkg --compare-versions "$1" ge "$2"
}

# Probe candidate versions above KNOWN_LATEST; print the newest existing URL
# and its version on stdout as "<version> <url>".
#
# Existence check: fetch response headers and look for "200" in the status
# line. (Parsing the header block rather than curl's exit code keeps this
# compatible with both real curl and the test mock.)
latest_release() {
  local best="$KNOWN_LATEST"
  local major minor patch v headers
  IFS=. read -r major minor patch <<<"$KNOWN_LATEST"
  local i=0
  while [ "$i" -lt "$PROBE_HIGHER" ]; do
    i=$((i + 1))
    patch=$((patch + 1))
    v="$major.$minor.$patch"
    headers="$(curl -sIL --max-time 15 "$(deb_url "$v")" 2>/dev/null || true)"
    if printf '%s\n' "$headers" | grep -q '^HTTP/.* 200'; then
      best="$v"
    fi
  done
  printf '%s %s\n' "$best" "$(deb_url "$best")"
}
