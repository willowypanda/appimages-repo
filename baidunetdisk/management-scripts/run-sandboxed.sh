#!/usr/bin/env bash
# Bubblewrap launcher for the Baidu Net Disk AppImage.
# Thin wrapper: sets app-specific knobs, then runs the shared launcher logic.
set -euo pipefail
APP_NAME="baidunetdisk"
APPIMAGE_GLOB='baidunetdisk-*.AppImage'
# Baidu Net Disk is an Electron app. It needs its resources next to the
# binary inside the extracted AppDir, which --appimage-extract-and-run
# provides. No extra allowlist entries beyond the shared set are required.
EXTRA_BWRAP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/.launcher-template.sh"
if [ ! -f "$TEMPLATE" ]; then
  echo "Internal error: $TEMPLATE missing (incomplete install)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$TEMPLATE"
