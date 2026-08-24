#!/usr/bin/env bash
# Shared appimagetool provisioning for all apps.
#
# Usage: ensure_appimagetool <output-path>
#   Ensures <output-path> is an executable, reasonably fresh appimagetool.
#
# Freshness: the tool is (re)downloaded if missing, older than TOOL_MAX_AGE
# days (default 30), or when FORCE_TOOL_REFRESH=1. The download is atomic:
# fetched to a temp file in the same directory, then renamed over the target,
# so a failed/interrupted download never leaves a broken tool behind.
#
# The canonical shared cache lives at ~/.cache/appimages-repo/appimagetool/;
# per-app copies are hard-linked from it when on the same filesystem, so N
# apps share one download without changing each script's local path.
set -euo pipefail

APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
TOOL_MAX_AGE_DAYS="${TOOL_MAX_AGE_DAYS:-30}"

ensure_appimagetool() {
  local dest="$1"
  local cache_dir="${HOME}/.cache/appimages-repo/appimagetool"
  local cache_tool="$cache_dir/appimagetool-x86_64.AppImage"

  mkdir -p "$cache_dir" "$(dirname "$dest")"

  _tool_is_fresh() { # path -> 0 if exists and younger than max age
    [ -x "$1" ] || return 1
    [ "${FORCE_TOOL_REFRESH:-0}" = "1" ] && return 1
    local mtime now age_days
    mtime="$(stat -c '%Y' "$1")"
    now="$(date +%s)"
    age_days=$(( (now - mtime) / 86400 ))
    [ "$age_days" -lt "$TOOL_MAX_AGE_DAYS" ]
  }

  # Refresh the shared cache when needed.
  if ! _tool_is_fresh "$cache_tool"; then
    local tmp
    tmp="$(mktemp "$cache_dir/.appimagetool.XXXXXX")"
    echo "[+] Fetching appimagetool (${TOOL_MAX_AGE_DAYS}-day refresh cycle)"
    curl --fail --location --progress-bar --max-time 600 "$APPIMAGETOOL_URL" -o "$tmp"
    chmod +x "$tmp"
    mv "$tmp" "$cache_tool"   # atomic within cache dir
  fi

  # Materialize at the requested path: hard-link if possible, else copy.
  if [ ! -x "$dest" ] || [ "${FORCE_TOOL_REFRESH:-0}" = "1" ]; then
    ln "$cache_tool" "$dest" 2>/dev/null || cp "$cache_tool" "$dest"
    chmod +x "$dest"
  fi
}

# Convenience wrapper so callers can do:  . ensure-appimagetool.sh; run_in_fuse_or_extract ...
run_appimagetool() { # tool args...
  local tool="$1"; shift
  if ! "$tool" "$@"; then
    "$tool" --appimage-extract-and-run "$@"
  fi
}
