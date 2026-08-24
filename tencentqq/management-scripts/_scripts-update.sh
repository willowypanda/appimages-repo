#!/usr/bin/env bash
# Shared helper: refresh this app's management-scripts from the repo.
#
# Usage: source _scripts-update.sh, then call:
#   update_management_scripts <app-name> <app-dir>
# Returns 0 on success (scripts now current), 1 on failure (existing
# scripts left untouched).
#
# Strategy: fetch the scripts directory listing from GitHub, download every
# file into a staging dir, validate required scripts exist, then swap into
# place. No manager dependency — works standalone.
set -uo pipefail

REPO_OWNER="${REPO_OWNER:-willowypanda}"
REPO_NAME="${REPO_NAME:-appimages-repo}"
BRANCH="${BRANCH:-main}"

update_management_scripts() { # $1 = app name, $2 = app_dir
  local app="$1" app_dir="$2"
  command -v curl >/dev/null 2>&1 || { echo "scripts-update: curl missing" >&2; return 1; }
  local tmp json name url
  tmp="$(mktemp -d "$app_dir/.scripts-download.XXXXXX")" || return 1
  if ! json="$(curl --fail --location --silent --show-error --max-time 60 \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${app}/management-scripts?ref=${BRANCH}")"; then
    rm -rf "$tmp"; return 1
  fi
  while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    case "$name" in
      *.sh|run|check|update|install|uninstall|shortcut)
        curl --fail --location --silent --show-error --max-time 60 "$url" -o "$tmp/$name" \
          || { rm -rf "$tmp"; echo "scripts-update: failed to fetch $name" >&2; return 1; }
        chmod +x "$tmp/$name"
        ;;
    esac
  done < <(python3 -c 'import json,sys; [print(x["name"]+"\t"+x["download_url"]) for x in json.load(sys.stdin) if x.get("type")=="file"]' <<<"$json")
  for required in run-sandboxed.sh run check update install uninstall shortcut; do
    [ -f "$tmp/$required" ] || { rm -rf "$tmp"; echo "scripts-update: fetched set missing $required" >&2; return 1; }
  done
  # All-or-nothing swap into management-scripts/.
  cp -a "$tmp"/. "$app_dir/management-scripts/" \
    || { rm -rf "$tmp"; echo "scripts-update: swap failed" >&2; return 1; }
  rm -rf "$tmp"
  echo "Management scripts updated."
}
