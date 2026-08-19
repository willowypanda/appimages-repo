#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-sandboxed.sh --instance NAME [--appimage FILE] [--bwrap] [-- APP_ARGS...]

Each instance receives a separate HOME under ~/.local/share/adspower-appimage/instances/.
The host ~/Downloads directory is mounted read-write as the instance's ~/Downloads.
The bubblewrap mode uses an explicit read-only runtime allowlist and does not bind the host / root.
EOF
}
INSTANCE=""
APPIMAGE=""
ENGINE=bwrap
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "Error: --instance requires a value" >&2; exit 2; }; INSTANCE="$2"; shift 2 ;;
    --appimage) [ $# -ge 2 ] || { echo "Error: --appimage requires a value" >&2; exit 2; }; APPIMAGE="$2"; shift 2 ;;
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

if [ "$ENGINE" = bwrap ]; then
  command -v bwrap >/dev/null 2>&1 || { echo "bubblewrap is not installed" >&2; exit 1; }
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  HOST_DOWNLOADS="${HOME}/Downloads"
  mkdir -p "$HOST_DOWNLOADS"

  # Do not expose the host root filesystem. Build an explicit read-only
  # runtime view containing the directories needed by the AppImage/Electron.
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
    --ro-bind "$APPIMAGE" /opt/adspower.AppImage
    --bind "$INSTANCE_HOME" "$HOME"
    --bind "$HOST_DOWNLOADS" "$HOME/Downloads"
    --chdir "$HOME"
    --setenv HOME "$HOME"
    --setenv USER "${USER}"
    --setenv DISPLAY "${DISPLAY:-}"
    --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-}"
    --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    --share-net)

  # Minimal files needed for DNS, user identity, TLS and locale handling.
  for f in resolv.conf hosts nsswitch.conf passwd group localtime; do
    [ -e "/etc/$f" ] && cmd+=(--ro-bind "/etc/$f" "/etc/$f")
  done
  for d in ssl/certs ca-certificates fonts fontconfig icons zoneinfo; do
    [ -e "/etc/$d" ] && cmd+=(--ro-bind "/etc/$d" "/etc/$d")
    [ -e "/usr/share/$d" ] && cmd+=(--ro-bind "/usr/share/$d" "/usr/share/$d")
  done

  # Only pass through the graphics/audio sockets that are actually in use.
  if [ -d /tmp/.X11-unix ]; then
    cmd+=(--dir /tmp/.X11-unix --ro-bind /tmp/.X11-unix /tmp/.X11-unix)
  fi
  RUNTIME_PARENT="$(dirname "$XDG_RUNTIME_DIR")"
  cmd+=(--dir /run --dir /run/user --dir "$RUNTIME_PARENT" --dir "$XDG_RUNTIME_DIR")
  for socket in "${WAYLAND_DISPLAY:-}" pipewire-0 pulse/native; do
    [ -n "$socket" ] && [ -e "$XDG_RUNTIME_DIR/$socket" ] && \
      cmd+=(--ro-bind "$XDG_RUNTIME_DIR/$socket" "$XDG_RUNTIME_DIR/$socket")
  done
  if [ -e /dev/dri ]; then
    cmd+=(--dev-bind /dev/dri /dev/dri)
  fi
  for device in null zero full random urandom tty; do
    [ -e "/dev/${device}" ] && cmd+=(--dev-bind "/dev/${device}" "/dev/${device}")
  done

  exec "${cmd[@]}" /opt/adspower.AppImage --appimage-extract-and-run "${ARGS[@]}"
fi
