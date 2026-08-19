#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-sandboxed.sh --instance NAME [--appimage FILE] [--firejail|--bwrap] [-- APP_ARGS...]

Each instance receives a separate HOME under ~/.local/share/adspower-appimage/instances/.
EOF
}
INSTANCE=""
APPIMAGE=""
ENGINE="auto"
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance) INSTANCE="${2:?missing instance name}"; shift 2 ;;
    --appimage) APPIMAGE="${2:?missing AppImage path}"; shift 2 ;;
    --firejail) ENGINE=firejail; shift ;;
    --bwrap) ENGINE=bwrap; shift ;;
    --) shift; ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$INSTANCE" ] || { echo "--instance is required" >&2; exit 2; }
case "$INSTANCE" in *[!A-Za-z0-9._-]*|'') echo "Invalid instance name" >&2; exit 2 ;; esac
if [ -z "$APPIMAGE" ]; then
  APPIMAGE="$(find "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" -maxdepth 1 -type f -name 'adspower-*.AppImage' -print -quit)"
fi
[ -f "$APPIMAGE" ] || { echo "AppImage not found: $APPIMAGE" >&2; exit 1; }
APPIMAGE="$(readlink -f "$APPIMAGE")"
BASE="${XDG_DATA_HOME:-$HOME/.local/share}/adspower-appimage/instances"
INSTANCE_HOME="$BASE/$INSTANCE"
mkdir -p "$INSTANCE_HOME" "$INSTANCE_HOME/Downloads" "$INSTANCE_HOME/Documents/Adspower"
chmod 700 "$INSTANCE_HOME"

if [ "$ENGINE" = auto ]; then
  command -v bwrap >/dev/null 2>&1 && ENGINE=bwrap || ENGINE=firejail
fi

if [ "$ENGINE" = bwrap ]; then
  command -v bwrap >/dev/null 2>&1 || { echo "bubblewrap is not installed" >&2; exit 1; }
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  cmd=(bwrap --die-with-parent --new-session --unshare-pid --unshare-uts --unshare-ipc
    --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /opt
    --ro-bind "$APPIMAGE" /opt/adspower.AppImage
    --bind "$INSTANCE_HOME" "$HOME"
    --setenv HOME "$HOME" --setenv USER "${USER}" --setenv DISPLAY "${DISPLAY:-}"
    --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}" --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    --share-net)
  [ -d /tmp/.X11-unix ] && cmd+=(--dir /tmp/.X11-unix --ro-bind /tmp/.X11-unix /tmp/.X11-unix)
  [ -d "$XDG_RUNTIME_DIR" ] && cmd+=(--ro-bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR")
  exec "${cmd[@]}" /opt/adspower.AppImage "${ARGS[@]}"
fi

command -v firejail >/dev/null 2>&1 || { echo "firejail is not installed" >&2; exit 1; }
exec firejail --quiet --private="$INSTANCE_HOME" --private-tmp \
  --whitelist="$INSTANCE_HOME/Downloads" \
  --whitelist="$INSTANCE_HOME/Documents" \
  "$APPIMAGE" "${ARGS[@]}"
