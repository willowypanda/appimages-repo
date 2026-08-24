#!/usr/bin/env bash
# Tencent QQ NT (tencentqq) management: shared constants and helpers.
#
# Upstream serves the official Linux AppImage behind a signed-URL gate:
#   1. GET https://qq-web.cdn-go.cn/im.qq.com_new/latest/rainbow/pcConfig.json
#      -> .Linux.x64DownloadUrl.appimage (unsigned; direct access returns 403)
#   2. POST https://im.qq.com/http2rpc/gotrpc/noauth/trpc.qqntv2.urlsign.UrlSign/GetSign
#      with {"url": <unsigned>} and header x-oidb -> returns {data:{url:<signed>}}
#   3. Download the signed URL (valid for a limited time).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="tencentqq"
PC_CONFIG_URL="https://qq-web.cdn-go.cn/im.qq.com_new/latest/rainbow/pcConfig.json"
URLSIGN_URL="https://im.qq.com/http2rpc/gotrpc/noauth/trpc.qqntv2.urlsign.UrlSign/GetSign"
URLSIGN_OIDB_HEADER='x-oidb: {"uint32_command":"0x9b8e","uint32_service_type":1}'
TARGET="$APP_DIR/QQ-x86_64.AppImage"
MARKER="$APP_DIR/.release-tag"

# Print "<version> <appimage-url>" for the latest Linux x64 build.
latest_release() {
  local json url version
  json="$(curl --fail --location --silent --show-error --max-time 60 "$PC_CONFIG_URL")"
  version="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["Linux"]["version"])')"
  url="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["Linux"]["x64DownloadUrl"]["appimage"])')"
  printf '%s %s\n' "$version" "$url"
}

# Exchange an unsigned CDN URL for a signed one.
signed_url() {
  local unsigned="$1" cookie signed
  cookie="$(mktemp)"
  curl --fail --silent --max-time 30 -c "$cookie" "https://im.qq.com" >/dev/null
  signed="$(curl --fail --silent --show-error --max-time 30 --json "{\"url\":\"$unsigned\"}" \
    -b "$cookie" "$URLSIGN_URL" -H "$URLSIGN_OIDB_HEADER" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["url"])')"
  rm -f "$cookie"
  printf '%s\n' "$signed"
}

# Download the latest AppImage to stdout-target path $1.
download_appimage() {
  local out="$1" meta url signed
  meta="$(latest_release)"
  url="$(printf '%s' "$meta" | awk '{print $2}')"
  signed="$(signed_url "$url")"
  curl --fail --location --progress-bar --max-time 1800 "$signed" -o "$out"
  chmod +x "$out"
}
