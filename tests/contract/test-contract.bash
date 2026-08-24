#!/usr/bin/env bash
# Contract tests: what ANY app's management-scripts must satisfy
# (README "Adding another app" promises, made executable).
# Runs against the adspower scripts via tests/apps/adspower/config.sh.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
. "$LIB/lib.sh"

CONTRACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG="${APP_CONFIG:-$REPO_DIR/tests/apps/adspower/config.sh}"
# shellcheck source=/dev/null
. "$APP_CONFIG"

SCRIPTS_SRC="$REPO_DIR/$SCRIPTS_SUBDIR"

new_app_sandbox() {
  mk_sandbox; use_sandbox_env
  APP="$SANDBOX/home/CustomAppimages/$APP_NAME"
  mkdir -p "$APP"
  cp -r "$SCRIPTS_SRC" "$APP/management-scripts"
  # Fake installed AppImage + release marker.
  : > "$APP/${APPIMAGE_GLOB%\**}${FAKE_APPIMAGE_SUFFIX}"
  printf '%s\n' "$FAKE_RELEASE_TAG" > "$APP/.release-tag"
}

# --- Level 1: static contract ---------------------------------------------

t static-required-scripts-present -- true
for s in run-sandboxed.sh run check update install uninstall shortcut; do
  assert_file_exists "$SCRIPTS_SRC/$s"
done

t static-scripts-pass-bash-n -- true
for f in "$SCRIPTS_SRC"/*; do
  bash -n "$f" || _fail "bash -n failed for $f"
done
_pass

t static-scripts-executable -- true
for s in run-sandboxed.sh run check update install uninstall shortcut; do
  [ -x "$SCRIPTS_SRC/$s" ] || { _fail "not executable: $s"; continue; }
done
_pass

t static-no-foreign-app-hardcode -- true
# Scripts must not reference other apps' names.
hits="$(grep -rlE '/(wechat|telegram|whatsapp)([^a-z]|$)' "$SCRIPTS_SRC" 2>/dev/null | wc -l)"
assert_eq "$hits" "0" "foreign app names hardcoded"
_pass

# --- Level 2: behavioral contract ------------------------------------------

t behavior-run-creates-isolated-instance-home -- true
new_app_sandbox
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
export MOCK_BWRAP_RUN_TARGET=1   # let the mock actually run the target so mkdirs happen
out="$(cd "$SANDBOX/work" && bash "$APP/management-scripts/run" work --flag1 2>&1)"
if grep -q -- '--setenv' "$MOCK_BWRAP_LOG" || [ -f "$MOCK_BWRAP_LOG" ]; then _pass; else _fail "bwrap not invoked"; fi
instance_home="$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/work"
if [ ! -e "$instance_home" ]; then
  # XDG_DATA_HOME is set in the sandbox, so the launcher uses it instead.
  instance_home="$SANDBOX/xdg/data/${APP_DATA_DIRNAME}/instances/work"
fi
assert_file_exists "$instance_home"
perm="$(stat -c '%a' "$instance_home")"
assert_eq "$perm" "700" "instance home permissions"
cleanup_sandbox

t behavior-run-rejects-invalid-instance-name -- true
new_app_sandbox
out="$(cd "$SANDBOX/work" && bash "$APP/management-scripts/run" 'bad/name' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "invalid instance accepted"; fi
assert_contains "$out" "Invalid instance" "rejection message"
cleanup_sandbox

t behavior-shortcut-create-list-delete-sync-idempotent -- true
new_app_sandbox
S="$APP/management-scripts/shortcut"
out="$(bash "$S" create myinst 2>&1)"
assert_contains "$out" "Created" "create output"
f="$SANDBOX_HOME/.local/share/applications/${SHORTCUT_PREFIX}myinst.desktop"
assert_file_exists "$f"
before="$(cat "$f")"
out="$(bash "$S" create myinst 2>&1)"
after="$(cat "$f")"
assert_eq "$before" "$after" "existing shortcut not overwritten"
mkdir -p "$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/synced"
bash "$S" sync >/dev/null 2>&1
assert_file_exists "$SANDBOX_HOME/.local/share/applications/${SHORTCUT_PREFIX}synced.desktop"
out="$(bash "$S" list 2>&1)"
assert_contains "$out" "${SHORTCUT_PREFIX}myinst.desktop" "list shows shortcuts"
bash "$S" delete myinst >/dev/null 2>&1
assert_no_file "$f"
out="$(bash "$S" delete myinst 2>&1)"
assert_contains "$out" "does not exist" "delete idempotent"
cleanup_sandbox

t behavior-shortcut-exec-uses-absolute-path -- true
new_app_sandbox
S="$APP/management-scripts/shortcut"
bash "$S" create abscheck >/dev/null 2>&1
exec_line="$(grep '^Exec=' "$SANDBOX_HOME/.local/share/applications/${SHORTCUT_PREFIX}abscheck.desktop")"
case "$exec_line" in
  "Exec=$HOME/"*) _pass ;;
  *) _fail "Exec is not an absolute home path: $exec_line" ;;
esac
cleanup_sandbox

t behavior-uninstall-preserves-instance-data-by-default -- true
new_app_sandbox
U="$APP/management-scripts/uninstall"
mkdir -p "$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/keepme"
out="$(printf 'n\n' | bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "uninstall rc"
assert_file_exists "$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/keepme"
assert_no_file "$APP"
cleanup_sandbox

t behavior-uninstall-deletes-instance-data-on-confirm -- true
new_app_sandbox
U="$APP/management-scripts/uninstall"
mkdir -p "$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/gone"
out="$(printf 'y\n' | bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "uninstall rc"
assert_no_file "$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}"
assert_no_file "$APP"
cleanup_sandbox

t behavior-install-idempotent-with-marker -- true
new_app_sandbox
I="$APP/management-scripts/install"
# Provide a release API route whose latest asset IS the currently installed
# (marker-matching) release; the idempotence branch must then succeed and,
# crucially, must not re-download (curl log shows only the API call).
export MOCK_FIXTURES="$TESTS_DIR/fixtures/mock-curl"
export MOCK_CURL_LOG="$SANDBOX/curl.log"
mkdir -p "$MOCK_FIXTURES"
printf '%s\n' "$FAKE_RELEASE_TAG" > "$MOCK_FIXTURES/install-idempotent-tag"
cat > "$MOCK_FIXTURES/releases-latest.json" <<EOF
[{"tag_name":"$FAKE_RELEASE_TAG","assets":[{"name":"adspower-${FAKE_APPIMAGE_SUFFIX}","browser_download_url":"https://example.invalid/adspower-${FAKE_APPIMAGE_SUFFIX}"}]}]
EOF
cat > "$MOCK_FIXTURES/routes" <<'EOF'
releases?per_page	releases-latest.json
EOF
: > "$MOCK_CURL_LOG"
out="$(bash "$I" 2>&1)"; rc=$?
assert_eq "$rc" "0" "idempotent install rc: $out"
assert_contains "$out" "already installed" "idempotent message"
downloads="$(grep -c 'browser_download_url\|example.invalid/adspower-' "$MOCK_CURL_LOG" || true)"
assert_eq "$downloads" "0" "no asset download on idempotent install"
cleanup_sandbox

t behavior-install-failure-preserves-current-appimage -- true
new_app_sandbox
I="$APP/management-scripts/install"
printf '%s\n' "adspower-v0.0.1-deadbee" > "$APP/.release-tag"   # marker mismatch forces download attempt
img="$APP/${APPIMAGE_GLOB%\**}${FAKE_APPIMAGE_SUFFIX}"
echo current > "$img"
out="$(bash "$I" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "install should fail without a valid release route"; fi
content="$(cat "$img")"
assert_eq "$content" "current" "current AppImage untouched on failure"
cleanup_sandbox

summary
