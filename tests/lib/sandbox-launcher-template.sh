#!/usr/bin/env bash
# Shared launcher template for AppImage apps run under bubblewrap.
#
# Apps source this after setting:
#   APP_NAME        short name (e.g. wechat)
#   APPIMAGE_GLOB   glob for the installed AppImage in APP_DIR
# Optional overrides before sourcing:
#   EXTRA_BWRAP_ARGS=()   additional bwrap args appended before the target
#
# Contract: --instance NAME [--appimage FILE] [-- APP_ARGS...]
# Each instance gets a private HOME under $XDG_DATA_HOME/<app>-appimage/instances/.
# The host ~/Downloads is mounted read-write as the instance's ~/Downloads.
set -euo pipefail

usage() {
  cat <<EOF
Usage: run-sandboxed.sh --instance NAME [--appimage FILE] [-- APP_ARGS...]

Each instance receives a separate HOME under ~/.local/share/${APP_NAME}-appimage/instances/.
The host ~/Downloads directory is mounted read-write as the instance's ~/Downloads.
The bubblewrap launcher uses an explicit read-only runtime allowlist and does not bind the host / root.
EOF
}
INSTANCE=""
APPIMAGE=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "Error: --instance requires a value" >&2; exit 2; }; INSTANCE="$2"; shift 2 ;;
    --appimage) [ $# -ge 2 ] || { echo "Error: --appimage requires a value" >&2; exit 2; }; APPIMAGE="$2"; shift 2 ;;
    --) shift; ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$INSTANCE" ] || { echo "--instance is required" >&2; exit 2; }
case "$INSTANCE" in
  ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) echo "Invalid instance name" >&2; exit 2 ;;
esac
if [ -z "$APPIMAGE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  APPIMAGE="$(find "$APP_DIR" -maxdepth 1 -type f -name "$APPIMAGE_GLOB" -print -quit)"
fi
[ -f "$APPIMAGE" ] || { echo "AppImage not found: $APPIMAGE" >&2; exit 1; }
APPIMAGE="$(readlink -f "$APPIMAGE")"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BASE="$DATA_HOME/${APP_NAME}-appimage/instances"
INSTANCE_HOME="$BASE/$INSTANCE"
mkdir -p "$INSTANCE_HOME" "$INSTANCE_HOME/Downloads" "$INSTANCE_HOME/Documents"
chmod 700 "$INSTANCE_HOME"

# bubblewrap is the only supported launcher engine.
command -v bwrap >/dev/null 2>&1 || { echo "bubblewrap is not installed" >&2; exit 1; }
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_DOWNLOADS="${HOME}/Downloads"
mkdir -p "$HOST_DOWNLOADS"

SANDBOX_TARGET="/opt/${APP_NAME}.AppImage"

# Do not expose the host root filesystem. Build an explicit read-only
# runtime view containing the directories needed by the app.
cmd=(bwrap --die-with-parent --new-session
  --unshare-pid --unshare-uts --unshare-ipc
  --ro-bind /usr /usr
  --ro-bind /bin /bin
  --ro-bind /sbin /sbin
  --ro-bind /lib /lib
  --ro-bind /lib64 /lib64
  --ro-bind /sys /sys
  --proc /proc
  --dir /dev
  --tmpfs /dev/shm
  --tmpfs /tmp
  --tmpfs /opt
  --tmpfs /etc
  --dir /home
  --dir "$HOME"
  --ro-bind "$APPIMAGE" "$SANDBOX_TARGET"
  --bind "$INSTANCE_HOME" "$HOME"
  --bind "$HOST_DOWNLOADS" "$HOME/Downloads"
  --chdir "$HOME"
  --setenv HOME "$HOME"
  --setenv USER "${USER:-$(id -un)}"
  --setenv DISPLAY "${DISPLAY:-}"
  --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}"
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
  --share-net)

# Minimal files needed for DNS, user identity, TLS and locale handling.
for f in resolv.conf hosts nsswitch.conf passwd group localtime machine-id; do
  [ -e "/etc/$f" ] && cmd+=(--ro-bind "/etc/$f" "/etc/$f")
done
for d in ssl/certs ca-certificates fonts fontconfig icons zoneinfo; do
  [ -e "/etc/$d" ] && cmd+=(--ro-bind "/etc/$d" "/etc/$d")
  [ -e "/usr/share/$d" ] && cmd+=(--ro-bind "/usr/share/$d" "/usr/share/$d")
done

# Only pass through the graphics/audio sockets that are actually in use.
# Unix sockets work over read-only bind mounts; connect(2) is unaffected.
if [ -d /tmp/.X11-unix ]; then
  cmd+=(--dir /tmp/.X11-unix --ro-bind /tmp/.X11-unix /tmp/.X11-unix)
fi
RUNTIME_PARENT="$(dirname "$XDG_RUNTIME_DIR")"
cmd+=(--dir /run --dir /run/user --dir "$RUNTIME_PARENT" --dir "$XDG_RUNTIME_DIR")
session_bus="$XDG_RUNTIME_DIR/bus"
wayland_socket="${WAYLAND_DISPLAY:-wayland-0}"
for socket in "$wayland_socket" pipewire-0 pulse/native bus; do
  [ -n "$socket" ] && [ -e "$XDG_RUNTIME_DIR/$socket" ] && \
    cmd+=(--ro-bind "$XDG_RUNTIME_DIR/$socket" "$XDG_RUNTIME_DIR/$socket")
done
[ -S "$session_bus" ] && cmd+=(--ro-bind "$session_bus" "$session_bus")

if [ -e /dev/dri ]; then
  cmd+=(--dev-bind /dev/dri /dev/dri)
fi
for device in null zero full random urandom tty; do
  [ -e "/dev/${device}" ] && cmd+=(--dev-bind "/dev/${device}" "/dev/${device}")
done

cmd+=("${EXTRA_BWRAP_ARGS[@]}")

exec "${cmd[@]}" "$SANDBOX_TARGET" --appimage-extract-and-run "${ARGS[@]}"
