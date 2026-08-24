#!/usr/bin/env bash
# Bubblewrap launcher for the Tencent QQ NT AppImage.
set -euo pipefail
APP_NAME="tencentqq"
APPIMAGE_GLOB='QQ*.AppImage'
EXTRA_BWRAP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/.launcher-template.sh"
if [ ! -f "$TEMPLATE" ]; then
  echo "Internal error: $TEMPLATE missing (incomplete install)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$TEMPLATE"
