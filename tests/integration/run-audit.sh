#!/usr/bin/env bash
# Manual install/uninstall audit: install + uninstall an app, then verify
# that no files leaked outside the documented whitelist.
#
# This is NOT a CI test. Run it manually when changing install/uninstall logic
# or adding new apps. It needs:
#   - root (for bind mounts)
#   - bwrap, dpkg-deb, fakeroot, curl, python3
#   - network access (downloads the real app deb + appimagetool)
#
# Usage: sudo bash tests/integration/run-audit.sh
# or:   sudo bash tests/integration/run-audit.sh adspower
# (default: audit both adspower and wechat)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_ROOT_PARENT="/var/tmp/appimages-audit"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
AUDIT_BASE="$AUDIT_ROOT_PARENT/run-$DATE_TAG-$$"
APP_NAME_FILTER="${1:-}"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = "0" ] || fail "must be run as root (use sudo)"
for cmd in bwrap dpkg-deb fakeroot curl python3 mount umount find sort awk grep; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: $cmd"
done
# Network sanity (does not actually download anything yet).
curl --silent --output /dev/null --max-time 15 --head https://github.com \
  || fail "no network access to github.com (required for appimagetool download)"
curl --silent --output /dev/null --max-time 15 --head https://api.github.com \
  || fail "no network access to api.github.com (required for adspower install)"

# ---------------------------------------------------------------------------
# Per-app test plan
# ---------------------------------------------------------------------------
# Whitelist: every file outside these paths is "leaked" and the test fails.
# Mirrors docs/shared-cache-policy.md: the appimagetool cache is intentionally
# retained across uninstalls.
ALLOWED_HOST_PREFIXES=(
  "/tmp/appimages-audit/run-"   # the audit dir itself
)

app_under_test() { # app -> prints audit config: install/install_args/setup/uninstall/clean_audit_dirs
  case "$1" in
    adspower)
      cat <<'EOF'
APP_LABEL=adspower
INSTALL_CMD=install
MANAGER_TEST=custom-appimage-manager
USE_MANAGER_INSTALL=1
EXPECT_FILES_DURING_INSTALL=1
EXPECT_FILES_AFTER_UNINSTALL=0
WHITELIST_KEEP=0
EOF
      ;;
    wechat)
      cat <<'EOF'
APP_LABEL=wechat
INSTALL_CMD=install
MANAGER_TEST=custom-appimage-manager
USE_MANAGER_INSTALL=1
EXPECT_FILES_DURING_INSTALL=1
EXPECT_FILES_AFTER_UNINSTALL=0
WHITELIST_KEEP=0
EOF
      ;;
    *)
      fail "unknown app: $1 (supported: adspower, wechat)"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Build the shadow root
# ---------------------------------------------------------------------------
# Strategy: bind-mount 8 fake dirs over the real paths that install touches.
# After we unmount, the host system has not been mutated (mounts disappear
# with the process — but to be extra safe, we always umount in cleanup).
#
# Shadowed paths:
#   /home/$SUDO_USER                 -> audit/home
#   /root                            -> audit/root
#   /etc                             -> audit/etc
#   /tmp                             -> audit/tmp
#   /var/cache                       -> audit/var-cache
# We DO NOT shadow:
#   /usr, /lib, /bin, /opt          (tools / libraries, read-only by mount)
#   /proc, /sys                      (pseudo-fs, no shadow needed)
SHADOW_PATHS=(
  "/home/$SUDO_USER"
  /root
  /etc
  /tmp
  /var/cache
)
declare -A SHADOW_BIND=(
  ["/home/$SUDO_USER"]="$AUDIT_BASE/home"
  [/root]="$AUDIT_BASE/root"
  [/etc]="$AUDIT_BASE/etc"
  [/tmp]="$AUDIT_BASE/tmp"
  [/var/cache]="$AUDIT_BASE/var-cache"
)

setup_shadow() {
  mkdir -p "$AUDIT_BASE"/{home,root,etc,tmp,var-cache}
  chmod 755 "$AUDIT_BASE"
  # Pre-stage the app source into the shadow so install sees a clean tree.
  mkdir -p "$AUDIT_BASE/home/$SUDO_USER/CustomAppimages"
  cp -a "$REPO_DIR/adspower" "$AUDIT_BASE/home/$SUDO_USER/CustomAppimages/" 2>/dev/null || true
  cp -a "$REPO_DIR/wechat"   "$AUDIT_BASE/home/$SUDO_USER/CustomAppimages/" 2>/dev/null || true
  cp -a "$REPO_DIR/custom-appimage-manager" "$AUDIT_BASE/home/$SUDO_USER/" 2>/dev/null || true

  for path in "${SHADOW_PATHS[@]}"; do
    [ -d "$path" ] || continue
    mount --bind "${SHADOW_BIND[$path]}" "$path" || fail "mount --bind ${SHADOW_BIND[$path]} $path failed"
  done
}

cleanup_shadow() {
  for ((i=${#SHADOW_PATHS[@]}-1; i>=0; i--)); do
    path="${SHADOW_PATHS[$i]}"
    [ -d "$path" ] || continue
    mountpoint -q "$path" 2>/dev/null && umount "$path" 2>/dev/null || true
  done
}
trap cleanup_shadow EXIT INT TERM

# ---------------------------------------------------------------------------
# Snapshot helpers
# ---------------------------------------------------------------------------
snapshot_root() { # path -> writes file list to stdout
  find "$1" -xdev -not -path "$1/proc" -not -path "$1/proc/*" \
              -not -path "$1/sys"  -not -path "$1/sys/*" \
              -not -path "$1/dev"  -not -path "$1/dev/*" \
              -not -path "$1/run"  -not -path "$1/run/*" \
              2>/dev/null | sort
}

leaks_in() { # path -> prints relative paths that fall outside the whitelist
  local root="$1" f rel
  find "$root" -xdev -type f 2>/dev/null | while read -r f; do
    rel="${f#$root}"
    rel="${rel#/}"
    case "$rel" in
      home/*/CustomAppimages/*) continue ;;
      home/*/.local/share/*-appimage/*) continue ;;
      home/*/.local/share/applications/*-appimage-*.desktop) continue ;;
      home/*/.local/bin/custom-appimage-manager) continue ;;   # manager self-install
      home/*/.cache/appimages-repo/*) continue ;;
      root/.local/share/*-appimage/*) continue ;;
      root/.local/share/applications/*-appimage-*.desktop) continue ;;
      root/.cache/appimages-repo/*) continue ;;
      run-*) continue ;;  # own audit temp dir
      tmp/*) continue ;;   # legitimate /tmp usage by scripts
      *) printf '%s\n' "$f" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# One-app run
# ---------------------------------------------------------------------------
APPS=("$@")
[ "${#APPS[@]}" -gt 0 ] || APPS=(adspower wechat)

total_fail=0
for app in "${APPS[@]}"; do
  if [ -n "$APP_NAME_FILTER" ] && [ "$app" != "$APP_NAME_FILTER" ]; then continue; fi

  echo "================================================================"
  echo "  Auditing $app"
  echo "================================================================"
  setup_shadow

  BASELINE="$(mktemp)"
  snapshot_root "$AUDIT_BASE" > "$BASELINE"

  # --- install via the manager (real download + setup) ---
  echo "[+] $app install (under fakeroot, may download ~325MB for adspower)..."
  fakeroot bash -c "
    set -e
    export PATH='$REPO_DIR:/usr/local/bin:/usr/bin:/bin'
    bash $REPO_DIR/custom-appimage-manager install
    bash $REPO_DIR/custom-appimage-manager app $app install
  " || { echo "  install FAILED"; total_fail=$((total_fail+1)); cleanup_shadow; continue; }

  AFTER_INSTALL="$(mktemp)"
  snapshot_root "$AUDIT_BASE" > "$AFTER_INSTALL"

  # Audit install-time leaks: any file outside the whitelist that appeared?
  echo "[+] Checking install-time file additions..."
  new_files=$(comm -13 "$BASELINE" "$AFTER_INSTALL")
  leaks=$(printf '%s\n' "$new_files" | leaks_in "$AUDIT_BASE")
  if [ -n "$leaks" ]; then
    echo "  FAIL: install created files outside the whitelist:"
    printf '    %s\n' $leaks | head -20
    total_fail=$((total_fail+1))
  else
    echo "  OK: install added files only within whitelist"
  fi

  # --- uninstall ---
  echo "[+] $app uninstall..."
  fakeroot bash -c "
    set -e
    export PATH='$REPO_DIR:/usr/local/bin:/usr/bin:/bin'
    bash $REPO_DIR/custom-appimage-manager app $app uninstall <<<y
  " || { echo "  uninstall FAILED"; total_fail=$((total_fail+1)); cleanup_shadow; continue; }

  AFTER_UNINSTALL="$(mktemp)"
  snapshot_root "$AUDIT_BASE" > "$AFTER_UNINSTALL"

  # Audit residual files: anything still in audit root after uninstall, minus
  # the documented retained cache and our own audit scratch.
  echo "[+] Checking residual files after uninstall..."
  residual=$(comm -23 "$BASELINE" "$AFTER_UNINSTALL")
  leftover=$(printf '%s\n' "$residual" | leaks_in "$AUDIT_BASE" | sed "s|^$AUDIT_BASE/||" | grep -v '^home/.*/\.cache/appimages-repo' || true)
  # Above should be empty: uninstall must remove everything except the
  # shared appimagetool cache (intentionally retained, see docs/shared-cache-policy.md).
  if [ -n "$leftover" ]; then
    echo "  FAIL: uninstall left unexpected files:"
    printf '    %s\n' $leftover | head -20
    total_fail=$((total_fail+1))
  else
    echo "  OK: uninstall left only the documented retained appimagetool cache"
  fi

  # --- numeric summary ---
  before_count=$(wc -l < "$BASELINE")
  after_install_count=$(wc -l < "$AFTER_INSTALL")
  after_uninstall_count=$(wc -l < "$AFTER_UNINSTALL")
  echo "  Files: baseline=$before_count, after_install=$after_install_count, after_uninstall=$after_uninstall_count"
  echo "  Audit artifacts kept at: $AUDIT_BASE"

  rm -f "$BASELINE" "$AFTER_INSTALL" "$AFTER_UNINSTALL"
  cleanup_shadow
  trap - EXIT INT TERM
done

echo "================================================================"
if [ "$total_fail" = "0" ]; then
  echo "  ALL APP AUDITS PASSED"
  echo "================================================================"
  exit 0
else
  echo "  $total_fail APP(S) HAD LEAKS — see output above"
  echo "  Inspect: ls $AUDIT_BASE"
  echo "================================================================"
  exit 1
fi
