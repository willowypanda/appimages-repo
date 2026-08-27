#!/usr/bin/env bash
# Manual end-to-end install/uninstall audit.
#
# Run as: sudo bash tests/integration/run-audit.sh [adspower|wechat]
# This is intentionally NOT part of CI. It downloads real upstream artifacts.
#
# The child process enters a private mount namespace before mounting any
# shadow directories. Consequently the host's /home, /tmp, and /var/cache
# mounts are never replaced globally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_PARENT="/tmp/appimages-audit"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
AUDIT_BASE="$AUDIT_PARENT/$RUN_ID"
APP_FILTER="${1:-}"
TARGET_USER="${SUDO_USER:-${USER:-}}"
TARGET_HOME=""
FAKEROOT_BIN=""
BASH_BIN=""

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Resolve tools before any namespace or mount operation. Use absolute paths
# for the fakeroot and bash invocations so sudo's PATH cannot break them.
[ "$(id -u)" -eq 0 ] || fail "run with sudo (root is required)"
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || fail "cannot resolve home for $TARGET_USER"
FAKEROOT_BIN="$(command -v fakeroot 2>/dev/null || true)"
BASH_BIN="$(command -v bash 2>/dev/null || true)"
[ -n "$FAKEROOT_BIN" ] || fail "fakeroot is not installed; run: sudo apt install fakeroot"
[ -n "$BASH_BIN" ] || fail "bash is not available in the root PATH"
for cmd in unshare mount umount mountpoint dpkg-deb curl python3 find sort grep awk sha256sum stat getent; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: $cmd"
done
curl --silent --show-error --fail --head --max-time 15 https://github.com >/dev/null \
  || fail "network check failed for github.com"

APPS=(adspower wechat)
[ -z "$APP_FILTER" ] || APPS=("$APP_FILTER")
case "$APP_FILTER" in ''|adspower|wechat) ;; *) fail "unknown app: $APP_FILTER (supported: adspower, wechat)" ;; esac

cleanup() {
  # Child mount namespaces disappear when their command exits. This removes
  # only the audit workspace itself, never a host directory mounted above it.
  rm -rf "$AUDIT_BASE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$AUDIT_BASE/home/$TARGET_USER" "$AUDIT_BASE/tmp" "$AUDIT_BASE/var-cache"
chmod 700 "$AUDIT_BASE" "$AUDIT_BASE/home/$TARGET_USER"
for app in "${APPS[@]}"; do
  mkdir -p "$AUDIT_BASE/home/$TARGET_USER/CustomAppimages/$app"
  # Include dotfiles: .launcher-template.sh and helper scripts are part of
  # the management-script installation contract.
  cp -a "$REPO_DIR/$app/management-scripts/." \
    "$AUDIT_BASE/home/$TARGET_USER/CustomAppimages/$app/management-scripts/"
done

snapshot() {
  local root="$AUDIT_BASE" f rel mode hash
  find "$AUDIT_BASE/home/$TARGET_USER" "$AUDIT_BASE/tmp" "$AUDIT_BASE/var-cache" \
    -xdev -type f -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
      rel="${f#$root/}"
      mode="$(stat -c '%a' "$f")"
      hash="$(sha256sum "$f" | awk '{print $1}')"
      printf '%s\t%s\t%s\n' "$rel" "$mode" "$hash"
    done | sort
}

paths_only() {
  # comm requires byte-sorted unique inputs. Re-sort after dropping metadata
  # columns instead of relying on the full snapshot's sort order.
  cut -f1 "$1" | LC_ALL=C sort -u
}

allowed_created_path() {
  case "$1" in
    home/*/CustomAppimages/*) return 0 ;;
    home/*/.local/share/*-appimage/*) return 0 ;;
    home/*/.local/share/applications/*-appimage-*.desktop) return 0 ;;
    home/*/.local/bin/custom-appimage-manager) return 0 ;;
    home/*/.cache/appimages-repo/*) return 0 ;;
    tmp/*|var-cache/*) return 0 ;;
    *) return 1 ;;
  esac
}

new_or_changed_outside() {
  local before="$1" after="$2" rel
  awk -F '\t' 'NR==FNR { old[$1]=$0; next } { new[$1]=$0 }
    END {
      for (p in new) if (!(p in old) || new[p] != old[p]) print p
    }' "$before" "$after" | sort -u |
    while IFS= read -r rel; do
      [ -z "$rel" ] || allowed_created_path "$rel" || printf '%s\n' "$rel"
    done
}

new_noncache_files() {
  local before="$1" after="$2" rel
  comm -13 <(paths_only "$before") <(paths_only "$after") |
    while IFS= read -r rel; do
      case "$rel" in
        home/*/.cache/appimages-repo/*) ;;
        *) printf '%s\n' "$rel" ;;
      esac
    done
}

run_in_namespace() { # mode app app_root
  local mode="$1" app="$2" app_root="$3"
  local app_q root_q home_q user_q fake_q
  app_q=$(printf '%q' "$app")
  root_q=$(printf '%q' "$AUDIT_BASE")
  # Keep the parent-computed absolute paths in the child environment. The
  # function is copied into a new bash by unshare, so only exported variables
  # survive into that shell; these q variables are local and are expanded in
  # the command strings below before execution.
  home_q=$(printf '%q' "$TARGET_HOME")
  user_q=$(printf '%q' "$TARGET_USER")
  fake_q=$(printf '%q' "$FAKEROOT_BIN")
  local app_rel child_app_q
  app_rel="${app_root#"$AUDIT_BASE"}"
  child_app_q=$(printf '%q' "/audit$app_rel")
  if [ "$mode" = install ]; then
    "$BASH_BIN" -c "
      set -euo pipefail
      mount --make-rprivate /
      mkdir -p /audit
      # Make the audit tree visible at /audit before replacing /tmp. The
      # audit tree itself lives under /tmp, which becomes hidden below.
      mount --bind $root_q /audit
      mount --bind $root_q/home/$user_q $home_q
      mount --bind $root_q/var-cache /var/cache
      mount --bind $root_q/tmp /tmp
      export HOME=$home_q USER=$user_q
      export XDG_CONFIG_HOME=\"\$HOME/.config\"
      export XDG_DATA_HOME=\"\$HOME/.local/share\"
      export XDG_CACHE_HOME=\"\$HOME/.cache\"
      export TMPDIR=/tmp
      export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      cd $child_app_q
      $fake_q bash ./management-scripts/install
    "
  else
    "$BASH_BIN" -c "
      set -euo pipefail
      mount --make-rprivate /
      mkdir -p /audit
      # Make the audit tree visible at /audit before replacing /tmp. The
      # audit tree itself lives under /tmp, which becomes hidden below.
      mount --bind $root_q /audit
      mount --bind $root_q/home/$user_q $home_q
      mount --bind $root_q/var-cache /var/cache
      mount --bind $root_q/tmp /tmp
      export HOME=$home_q USER=$user_q
      export XDG_CONFIG_HOME=\"\$HOME/.config\"
      export XDG_DATA_HOME=\"\$HOME/.local/share\"
      export XDG_CACHE_HOME=\"\$HOME/.cache\"
      export TMPDIR=/tmp
      export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      cd $child_app_q
      printf 'y\n' | $fake_q bash ./management-scripts/uninstall
    "
  fi
}

for app in "${APPS[@]}"; do
  echo "================================================================"
  echo "  Auditing $app"
  echo "================================================================"
  APP_ROOT="$AUDIT_BASE/home/$TARGET_USER/CustomAppimages/$app"
  BEFORE="$AUDIT_BASE/before-$app.list"
  AFTER_INSTALL="$AUDIT_BASE/after-install-$app.list"
  AFTER_UNINSTALL="$AUDIT_BASE/after-uninstall-$app.list"
  snapshot > "$BEFORE"

  # These are consumed by run_in_namespace after its function definition is
  # copied into the child shell.
  export AUDIT_BASE TARGET_HOME TARGET_USER FAKEROOT_BIN BASH_BIN
  echo "[+] install (real upstream download/repack where applicable)..."
  if ! unshare --mount --fork --pid --mount-proc "$BASH_BIN" -c \
      "$(declare -f run_in_namespace); $(declare -f fail); run_in_namespace install '$app' '$APP_ROOT'"; then
    echo "  install FAILED" >&2
    exit 1
  fi
  snapshot > "$AFTER_INSTALL"

  echo "[+] checking install additions and modifications..."
  leaks="$(new_or_changed_outside "$BEFORE" "$AFTER_INSTALL")"
  if [ -n "$leaks" ]; then
    echo "  FAIL: install changed paths outside whitelist:"
    printf '    %s\n' "$leaks"
    exit 1
  fi
  echo "  OK: install changes are within whitelist"

  echo "[+] uninstall (instance deletion explicitly confirmed)..."
  if ! unshare --mount --fork --pid --mount-proc "$BASH_BIN" -c \
      "$(declare -f run_in_namespace); $(declare -f fail); run_in_namespace uninstall '$app' '$APP_ROOT'"; then
    echo "  uninstall FAILED" >&2
    exit 1
  fi
  snapshot > "$AFTER_UNINSTALL"

  # The app directory must be completely gone. The shared cache is allowed to
  # survive, but it is outside APP_ROOT and intentionally retained.
  if [ -e "$APP_ROOT" ]; then
    echo "  FAIL: app directory still exists after uninstall: $APP_ROOT" >&2
    exit 1
  fi
  echo "[+] checking residual files..."
  residual="$(new_noncache_files "$BEFORE" "$AFTER_UNINSTALL")"
  if [ -n "$residual" ]; then
    echo "  FAIL: unexpected residual files:"
    printf '    %s\n' "$residual"
    exit 1
  fi
  echo "  OK: uninstall left no unexpected files (shared cache may remain)"
  echo "  Audit shadow: $AUDIT_BASE"
done

echo "================================================================"
echo "  ALL AUDITS PASSED"
echo "================================================================"
