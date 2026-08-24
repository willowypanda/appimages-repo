#!/usr/bin/env bash
# WeChat Linux AppImage management scripts.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="wechat"
DOWNLOAD_URL="https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage"
TARGET="$APP_DIR/WeChatLinux_x86_64.AppImage"
MARKER="$APP_DIR/.release-tag"

installed_version() {
  # Version marker: upstream serves a fixed-URL rolling file; we record the
  # download date + content length as a change-detection tag.
  cat "$MARKER" 2>/dev/null || true
}

remote_tag() {
  # Last-Modified + Content-Length identify the current upstream file without
  # downloading it. Note: mawk lacks IGNORECASE; match via tolower().
  local hdr
  hdr="$(curl --fail --location --silent --show-error --head --max-time 30 "$DOWNLOAD_URL" | tr -d '\r')"
  printf '%s|%s\n' \
    "$(printf '%s\n' "$hdr" | awk 'tolower($0) ~ /^last-modified:/ {print $NF, $(NF-1), $(NF-2)}')" \
    "$(printf '%s\n' "$hdr" | awk 'tolower($0) ~ /^content-length:/ {print $2}')"
}
