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
  : > "$APP/$FAKE_APPIMAGE_NAME"
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
  [ -x "$SCRIPTS_SRC/$s" ] || _fail "not executable: $s"
done

# --- Level 2: behavioral contract ------------------------------------------

t behavior-run-creates-isolated-instance-home -- true
new_app_sandbox
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
export MOCK_BWRAP_RUN_TARGET=1   # let the mock actually run the target so mkdirs happen
out="$(cd "$SANDBOX/work" && bash "$APP/management-scripts/run" work --flag1 2>&1)"
assert_file_exists "$MOCK_BWRAP_LOG"
instance_home="$SANDBOX_HOME/.local/share/${APP_DATA_DIRNAME}/instances/work"
if [ ! -e "$instance_home" ]; then
  # XDG_DATA_HOME is set in the sandbox, so the launcher uses it instead.
  instance_home="$SANDBOX/xdg/data/${APP_DATA_DIRNAME}/instances/work"
fi
assert_file_exists "$instance_home"
perm="$(stat -c '%a' "$instance_home")"
assert_eq "$perm" "700" "instance home permissions"
# Verify the sandbox actually maps the instance directory as HOME: parse the
# NUL-separated bwrap argv and require --bind <instance_home> $HOME plus the
# matching --chdir/--setenv HOME.
mapfile -d '' -t bwrap_argv < "$MOCK_BWRAP_LOG"
bwrap_has_pair() {
  local first="$1" second="$2" i
  for ((i=0; i+1<${#bwrap_argv[@]}; i++)); do
    [ "${bwrap_argv[$i]}" = "$first" ] && [ "${bwrap_argv[$((i+1))]}" = "$second" ] && return 0
  done
  return 1
}
bwrap_has_triple() {
  local first="$1" second="$2" third="$3" i
  for ((i=0; i+2<${#bwrap_argv[@]}; i++)); do
    [ "${bwrap_argv[$i]}" = "$first" ] && [ "${bwrap_argv[$((i+1))]}" = "$second" ] && \
      [ "${bwrap_argv[$((i+2))]}" = "$third" ] && return 0
  done
  return 1
}
if bwrap_has_triple "--bind" "$instance_home" "$HOME"; then _pass; else _fail "instance HOME not bound to \$HOME"; fi
if bwrap_has_triple "--setenv" "HOME" "$HOME"; then _pass; else _fail "--setenv HOME missing/incorrect"; fi
if bwrap_has_pair "--chdir" "$HOME"; then _pass; else _fail "--chdir \$HOME missing"; fi
cleanup_sandbox

t behavior-run-rejects-invalid-instance-name -- true
for invalid_instance in 'bad/name' '.' '..' '...' '-leading'; do
  new_app_sandbox
  out="$(cd "$SANDBOX/work" && bash "$APP/management-scripts/run" "$invalid_instance" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then _pass; else _fail "invalid instance accepted: $invalid_instance"; fi
  assert_contains "$out" "Invalid instance" "rejection message for $invalid_instance"
  cleanup_sandbox
done

t behavior-shortcut-create-list-delete-sync-idempotent -- true
new_app_sandbox
S="$APP/management-scripts/shortcut"
out="$(bash "$S" create myinst 2>&1)"
assert_contains "$out" "Created" "create output"
desktop_dir="$XDG_DATA_HOME/applications"
f="$desktop_dir/${SHORTCUT_PREFIX}myinst.desktop"
assert_file_exists "$f"
before="$(cat "$f")"
out="$(bash "$S" create myinst 2>&1)"
after="$(cat "$f")"
assert_eq "$before" "$after" "existing shortcut not overwritten"
mkdir -p "$XDG_DATA_HOME/${APP_DATA_DIRNAME}/instances/synced"
bash "$S" sync >/dev/null 2>&1
assert_file_exists "$desktop_dir/${SHORTCUT_PREFIX}synced.desktop"
out="$(bash "$S" list 2>&1)"
assert_contains "$out" "${SHORTCUT_PREFIX}myinst.desktop" "list shows shortcuts"
bash "$S" delete myinst >/dev/null 2>&1
assert_no_file "$f"
out="$(bash "$S" delete myinst 2>&1)"
assert_contains "$out" "does not exist" "delete idempotent"
cleanup_sandbox

t behavior-shortcut-rejects-invalid-instance-names -- true
for invalid_instance in 'bad/name' '.' '..' '...' '-leading'; do
  new_app_sandbox
  S="$APP/management-scripts/shortcut"
  out="$(bash "$S" create "$invalid_instance" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then _pass; else _fail "shortcut accepted invalid instance: $invalid_instance"; fi
  assert_contains "$out" "Invalid instance" "shortcut rejection for $invalid_instance"
  cleanup_sandbox
done

t behavior-shortcut-exec-uses-absolute-path -- true
new_app_sandbox
S="$APP/management-scripts/shortcut"
bash "$S" create abscheck >/dev/null 2>&1
exec_line="$(grep '^Exec=' "$XDG_DATA_HOME/applications/${SHORTCUT_PREFIX}abscheck.desktop")"
case "$exec_line" in
  "Exec=$HOME/"*) _pass ;;
  *) _fail "Exec is not an absolute home path: $exec_line" ;;
esac
cleanup_sandbox

t behavior-uninstall-preserves-instance-data-by-default -- true
new_app_sandbox
U="$APP/management-scripts/uninstall"
mkdir -p "$XDG_DATA_HOME/${APP_DATA_DIRNAME}/instances/keepme"
mkdir -p "$XDG_DATA_HOME/applications"
: > "$XDG_DATA_HOME/applications/${SHORTCUT_PREFIX}keepme.desktop"
out="$(printf 'n\n' | bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "uninstall rc"
assert_file_exists "$XDG_DATA_HOME/${APP_DATA_DIRNAME}/instances/keepme"
assert_no_file "$XDG_DATA_HOME/applications/${SHORTCUT_PREFIX}keepme.desktop"
assert_no_file "$APP"
cleanup_sandbox

t behavior-uninstall-deletes-instance-data-on-confirm -- true
new_app_sandbox
U="$APP/management-scripts/uninstall"
mkdir -p "$XDG_DATA_HOME/${APP_DATA_DIRNAME}/instances/gone"
out="$(printf 'y\n' | bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "uninstall rc"
assert_no_file "$XDG_DATA_HOME/${APP_DATA_DIRNAME}"
assert_no_file "$APP"
cleanup_sandbox

t behavior-install-idempotent-with-marker -- true
new_app_sandbox
I="$APP/management-scripts/install"
# Provide a release API route whose latest asset IS the currently installed
# (marker-matching) release; the idempotence branch must then succeed and,
# crucially, must not re-download (curl log shows only the API call).
export MOCK_CURL_LOG="$SANDBOX/curl.log"
cat > "$MOCK_FIXTURES/releases-latest.json" <<EOF
[{"tag_name":"$FAKE_RELEASE_TAG","assets":[{"name":"$FAKE_APPIMAGE_NAME","browser_download_url":"https://example.invalid/$FAKE_APPIMAGE_NAME"}]}]
EOF
cat > "$MOCK_FIXTURES/routes" <<'EOF'
releases?per_page	releases-latest.json
EOF
: > "$MOCK_CURL_LOG"
out="$(bash "$I" 2>&1)"; rc=$?
assert_eq "$rc" "0" "idempotent install rc: $out"
assert_contains "$out" "already installed" "idempotent message"
downloads="$(grep -c "example.invalid/$FAKE_APPIMAGE_NAME" "$MOCK_CURL_LOG" || true)"
assert_eq "$downloads" "0" "no asset download on idempotent install"
cleanup_sandbox

t behavior-install-failure-preserves-current-appimage -- true
new_app_sandbox
I="$APP/management-scripts/install"
printf '%s\n' "adspower-v0.0.1-deadbee" > "$APP/.release-tag"   # marker mismatch forces download attempt
img="$APP/$FAKE_APPIMAGE_NAME"
echo current > "$img"
out="$(bash "$I" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "install should fail without a valid release route"; fi
content="$(cat "$img")"
assert_eq "$content" "current" "current AppImage untouched on failure"
cleanup_sandbox

summary
