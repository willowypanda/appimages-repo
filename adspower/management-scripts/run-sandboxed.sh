#!/usr/bin/env bash
# Bubblewrap launcher for the AdsPower Global AppImage.
# Thin wrapper: sets app-specific knobs, then runs the shared launcher logic.
set -euo pipefail
APP_NAME="adspower"
APPIMAGE_GLOB='adspower-*.AppImage'
# AdsPower is a self-contained Electron app; nothing extra beyond the shared
# allowlist (graphics/audio sockets, /dev/dri, ~/Downloads) is required.
EXTRA_BWRAP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/.launcher-template.sh"
if [ ! -f "$TEMPLATE" ]; then
  echo "Internal error: $TEMPLATE missing (incomplete install)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$TEMPLATE"
