#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_ARG=""
for arg in "$@"; do
  case "$arg" in
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) [ -z "$DEB_ARG" ] || { echo "Error: only one .deb file may be specified" >&2; exit 2; }
       DEB_ARG="$arg" ;;
  esac
done

DEB="${DEB_ARG:-${PROJECT_DIR}/deb_download/AdsPower-Global-*-x64.deb}"
if [ ! -f "$DEB" ]; then
  shopt -s nullglob
  candidates=("${PROJECT_DIR}/deb_download"/AdsPower-Global-*-x64.deb)
  shopt -u nullglob
  [ "${#candidates[@]}" -gt 0 ] || { echo "No .deb found; run ./download-latest.sh" >&2; exit 1; }
  DEB="${candidates[-1]}"
fi

BASENAME="$(basename "$DEB" .deb)"
VERSION="${BASENAME#AdsPower-Global-}"
VERSION="${VERSION%-x64}"
APP_ID="adspower-global"
APPDIR="${PROJECT_DIR}/AppDir"
EXTRACT="${PROJECT_DIR}/.deb-extracted"
TOOL="${PROJECT_DIR}/appimagetool-x86_64.AppImage"
OUTPUT="${PROJECT_DIR}/adspower-${VERSION}-x86_64.AppImage"

if [ ! -x "$TOOL" ]; then
  # Shared provisioning with a refresh cycle (see tests/lib/ensure-appimagetool.sh).
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/_ensure-appimagetool.sh"
  ensure_appimagetool "$TOOL"
fi

rm -rf "$EXTRACT" "$APPDIR"
# Remove stale build outputs so the post-build lookup cannot pick an old file.
find "$PROJECT_DIR" -maxdepth 1 -type f -name 'adspower-*-x86_64.AppImage' -delete
mkdir -p "$EXTRACT" "$APPDIR/usr/lib/${APP_ID}" "$APPDIR/usr/bin"
dpkg-deb -x "$DEB" "$EXTRACT"
cp -a "$EXTRACT/opt/AdsPower Global/." "$APPDIR/usr/lib/${APP_ID}/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
set -eu
APPDIR="$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
export PATH="$APPDIR/usr/bin:$PATH"
export ELECTRON_DISABLE_SANDBOX=1
export CHROME_DEVEL_SANDBOX=
export NODE_ENV=production
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config/adspower_global}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share/adspower_global}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache/adspower_global}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$HOME/Documents/Adspower"
exec "$APPDIR/usr/lib/adspower-global/adspower_global" "$@"
EOF
chmod +x "$APPDIR/AppRun"
ln -s ../lib/${APP_ID}/adspower_global "$APPDIR/usr/bin/adspower_global"

cat > "$APPDIR/${APP_ID}.desktop" <<'EOF'
[Desktop Entry]
Name=AdsPower
Exec=adspower_global %U
Terminal=false
Type=Application
Icon=adspower_global
StartupWMClass=AdsPower Global
Comment=AdsPower Global
Categories=Network;Utility;
EOF

for s in 16 24 32 48 64 128 256 512; do
  src="$EXTRACT/usr/share/icons/hicolor/${s}x${s}/apps/adspower_global.png"
  if [ -f "$src" ]; then
    mkdir -p "$APPDIR/usr/share/icons/hicolor/${s}x${s}/apps"
    cp "$src" "$APPDIR/usr/share/icons/hicolor/${s}x${s}/apps/adspower_global.png"
    [ "$s" = 256 ] && cp "$src" "$APPDIR/adspower_global.png"
  fi
done

rm -f "$OUTPUT"
# Remove any output the tool itself may have produced in a previous run
# (appimagetool names it after the desktop entry, e.g. AdsPower-x86_64).
rm -f "$PROJECT_DIR/AdsPower-x86_64.AppImage"
cd "$PROJECT_DIR"
if ! "$TOOL" "AppDir"; then
  "$TOOL" --appimage-extract-and-run "AppDir"
fi

# appimagetool derives its own output name from the desktop entry (here:
# "AdsPower-x86_64.AppImage"), which is not the versioned name we publish.
TOOL_OUTPUT="$PROJECT_DIR/AdsPower-x86_64.AppImage"
if [ -f "$TOOL_OUTPUT" ]; then
  mv "$TOOL_OUTPUT" "$OUTPUT"
elif [ -f "$OUTPUT" ]; then
  : # tool already wrote the expected name directly
else
  echo "AppImage output was not found" >&2
  exit 1
fi
echo "[+] Created $OUTPUT"
printf '{"version":"%s","appimage":"%s"}\n' "$VERSION" "$OUTPUT"
