#!/usr/bin/env bash
# Bubblewrap launcher for the WeChat Linux AppImage.
# Thin wrapper: sets app-specific knobs, then runs the shared launcher logic.
set -euo pipefail
APP_NAME="wechat"
APPIMAGE_GLOB='WeChatLinux_*.AppImage'
# WeChat is a self-contained AppImage; nothing extra beyond the shared
# allowlist (graphics/audio sockets, /dev/dri, ~/Downloads) is required.
EXTRA_BWRAP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate the shared launcher template shipped alongside the repo. When the
# management scripts are installed standalone, fall back to a vendored copy.
TEMPLATE="$SCRIPT_DIR/.launcher-template.sh"
if [ ! -f "$TEMPLATE" ]; then
  echo "Internal error: $TEMPLATE missing (incomplete install)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$TEMPLATE"
