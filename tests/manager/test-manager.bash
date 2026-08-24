#!/usr/bin/env bash
# Manager (custom-appimage-manager) behavior and security regression tests.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
. "$LIB/lib.sh"

MANAGER="$REPO_DIR/custom-appimage-manager"

new_case() { mk_sandbox; use_sandbox_env; }

# --- usage / contract ------------------------------------------------------

t usage-no-args -- bash "$MANAGER"
assert_rc 0 bash "$MANAGER"
t usage-help -- bash "$MANAGER" --help
assert_rc 0 bash "$MANAGER" --help
t unknown-command -- true
assert_rc 2 bash "$MANAGER" bogus-command
t install-extra-arg -- true
assert_rc 2 bash "$MANAGER" install extra

# --- app name security regressions -----------------------------------------

for bad in '..' '.' '...' '../outside' '../../evil' 'a/b' $'a\nb' '-x'; do
  t "invalid-app-rejected:$bad" -- true
  new_case
  out="$(bash "$MANAGER" app "$bad" run 2>&1)"; rc=$?
  assert_eq "$rc" "2" "rc for '$bad'"
  assert_contains "$out" "invalid app name" "error message for '$bad'"
  # No side effects anywhere in sandbox home.
  assert_empty_dir "$SANDBOX_HOME"
  cleanup_sandbox
done

t dotdot-cannot-execute-outside-script -- true
new_case
mkdir -p "$SANDBOX_HOME/CustomAppimages" "$SANDBOX_HOME/management-scripts"
printf '#!/bin/sh\necho PWNED_OUTSIDE\n' > "$SANDBOX_HOME/management-scripts/run"
chmod +x "$SANDBOX_HOME/management-scripts/run"
out="$(bash "$MANAGER" app .. run 2>&1)"; rc=$?
assert_eq "$rc" "2" "app .. rc"
assert_not_contains "$out" "PWNED_OUTSIDE" "must not execute outside script"
cleanup_sandbox

t update-all-skips-invalid-dirname -- true
new_case
mkdir -p "$SANDBOX_HOME/CustomAppimages/..evil/management-scripts" \
         "$SANDBOX_HOME/CustomAppimages/good/management-scripts"
printf '#!/bin/sh\necho good-ran\n' > "$SANDBOX_HOME/CustomAppimages/good/management-scripts/update"
chmod +x "$SANDBOX_HOME/CustomAppimages/"*/management-scripts/*
out="$(bash "$MANAGER" update-all 2>&1)"; rc=$?
# An invalid directory name counts as a failure in the summary (documented
# behavior): good apps are still updated, exit is non-zero.
assert_eq "$rc" "1" "invalid dir name fails summary"
assert_contains "$out" "good-ran" "good app updated"
assert_contains "$out" "..evil" "names invalid dir"
cleanup_sandbox

# --- dispatch ---------------------------------------------------------------

make_installed_app() { # name [script-behavior]
  local name="$1"
  mkdir -p "$SANDBOX_HOME/CustomAppimages/$name/management-scripts"
  printf '#!/bin/sh\necho ran:%s args:"$@"\n' "$name" > "$SANDBOX_HOME/CustomAppimages/$name/management-scripts/run"
  chmod +x "$SANDBOX_HOME/CustomAppimages/$name/management-scripts/run"
}

t app-dispatch-passes-args -- true
new_case
make_installed_app myapp
out="$(bash "$MANAGER" app myapp run inst1 --flag value 2>&1)"
assert_contains "$out" 'args:inst1 --flag value' "args passed through"
cleanup_sandbox

t app-dispatch-preserves-quoting -- true
new_case
make_installed_app qapp
out="$(bash "$MANAGER" app qapp run default 'two words' '*.glob' 2>&1)"
assert_contains "$out" 'args:default two words *.glob' "quoting preserved"
cleanup_sandbox

t run-shorthand-single-app-default-instance -- true
new_case
make_installed_app solo
out="$(bash "$MANAGER" run 2>&1)"
assert_contains "$out" "ran:solo args:default" "shorthand run uses default instance"
cleanup_sandbox

t run-shorthand-named-instance-and-args -- true
new_case
make_installed_app solo
out="$(bash "$MANAGER" run work --x 2>&1)"
assert_contains "$out" "ran:solo args:work --x" "named instance + args"
cleanup_sandbox

t run-shorthand-ambiguous-with-two-apps -- true
new_case
make_installed_app one; make_installed_app two
out="$(bash "$MANAGER" run 2>&1)"; rc=$?
assert_eq "$rc" "2" "ambiguous run rc"
assert_contains "$out" "specify an app" "ambiguity message"
cleanup_sandbox

t app-shortcut-convenience-resolves-single-app -- true
new_case
make_installed_app onlyone
mkdir -p "$SANDBOX_HOME/CustomAppimages/onlyone/management-scripts"
cp "$REPO_DIR/adspower/management-scripts/shortcut" \
   "$SANDBOX_HOME/CustomAppimages/onlyone/management-scripts/shortcut"
out="$(bash "$MANAGER" app shortcut list 2>&1)"; rc=$?
assert_eq "$rc" "0" "app shortcut list rc"
cleanup_sandbox

t not-installed-hint -- true
new_case
mkdir -p "$SANDBOX_HOME/CustomAppimages/someapp"   # dir exists but no scripts
out="$(bash "$MANAGER" app someapp run 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "should fail when script missing"; fi
assert_contains "$out" "not available" "hints the app is not usable"
assert_contains "$out" "someapp" "names the app"
cleanup_sandbox

# --- update-all semantics ---------------------------------------------------

t update-all-failure-does-not-stop-others -- true
new_case
for a in a-fail b-ok c-ok; do
  mkdir -p "$SANDBOX_HOME/CustomAppimages/$a/management-scripts"
done
printf '#!/bin/sh\necho a-ran; exit 9\n' > "$SANDBOX_HOME/CustomAppimages/a-fail/management-scripts/update"
printf '#!/bin/sh\necho b-ran\n'        > "$SANDBOX_HOME/CustomAppimages/b-ok/management-scripts/update"
printf '#!/bin/sh\necho c-ran\n'        > "$SANDBOX_HOME/CustomAppimages/c-ok/management-scripts/update"
chmod +x "$SANDBOX_HOME"/CustomAppimages/*/management-scripts/update
out="$(bash "$MANAGER" update-all 2>&1)"; rc=$?
assert_eq "$rc" "1" "summary exit code"
assert_contains "$out" "b-ran" "b still updated"
assert_contains "$out" "c-ran" "c still updated"
assert_contains "$out" "Failed to update: a-fail" "failure summary"
cleanup_sandbox

t update-all-empty-is-success -- true
new_case
out="$(bash "$MANAGER" update-all 2>&1)"; rc=$?
assert_eq "$rc" "0" "no apps installed"
assert_contains "$out" "No installed apps" "friendly message"
cleanup_sandbox

t update-all-missing-update-script-counts-as-failure -- true
new_case
mkdir -p "$SANDBOX_HOME/CustomAppimages/noupdate/management-scripts"
printf '#!/bin/sh\necho x\n' > "$SANDBOX_HOME/CustomAppimages/noupdate/management-scripts/check"
chmod +x "$SANDBOX_HOME/CustomAppimages/noupdate/management-scripts/check"
out="$(bash "$MANAGER" update-all 2>&1)"; rc=$?
assert_eq "$rc" "1" "missing update script fails the summary"
assert_contains "$out" "noupdate" "names failing app"
cleanup_sandbox

# --- self-update ------------------------------------------------------------

setup_local_repo_server() {
  # Serve fixture manager script from a file:// style route via mock curl.
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
}
fixture_manager_ok() {
  MOCK_FIXTURES="${MOCK_FIXTURES:-$TESTS_DIR/fixtures/mock-curl}"
  mkdir -p "$MOCK_FIXTURES"
  printf '#!/usr/bin/env bash\necho manager-v2\n' > "$MOCK_FIXTURES/manager-new"
}

t self-update-success -- true
new_case
mkdir -p "$SANDBOX_HOME/.local/bin" "$TESTS_DIR/fixtures/mock-curl"
export MOCK_FIXTURES="$TESTS_DIR/fixtures/mock-curl"
printf '#!/usr/bin/env bash\necho manager-v2\n' > "$MOCK_FIXTURES/manager-new"
cat > "$MOCK_FIXTURES/routes" <<EOF
raw.githubusercontent.com/willowypanda/appimages-repo/main/custom-appimage-manager	manager-new
EOF
printf '#!/usr/bin/env bash\necho manager-v1\n' > "$SANDBOX_HOME/.local/bin/custom-appimage-manager"
chmod +x "$SANDBOX_HOME/.local/bin/custom-appimage-manager"
out="$(bash "$MANAGER" self-update 2>&1)"; rc=$?
assert_eq "$rc" "0" "self-update rc: $out"
content="$(cat "$SANDBOX_HOME/.local/bin/custom-appimage-manager")"
assert_contains "$content" "manager-v2" "target replaced"
[ -x "$SANDBOX_HOME/.local/bin/custom-appimage-manager" ] && _pass || _fail "not executable after update"
leftovers="$(find "$SANDBOX_HOME/.local/bin" -name '.custom-appimage-manager.tmp.*' | wc -l)"
assert_eq "$leftovers" "0" "no tmp leftovers on success"
cleanup_sandbox

t self-update-http-failure-preserves-old-binary-and-no-tmp-leftover -- true
new_case
mkdir -p "$SANDBOX_HOME/.local/bin" "$TESTS_DIR/fixtures/mock-curl"
export MOCK_FIXTURES="$TESTS_DIR/fixtures/mock-curl"
: > "$MOCK_FIXTURES/empty"
cat > "$MOCK_FIXTURES/routes" <<EOF
custom-appimage-manager	status:404:empty
EOF
printf '#!/usr/bin/env bash\necho manager-old-intact\n' > "$SANDBOX_HOME/.local/bin/custom-appimage-manager"
chmod +x "$SANDBOX_HOME/.local/bin/custom-appimage-manager"
out="$(bash "$MANAGER" self-update 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "self-update should fail on HTTP error"; fi
content="$(cat "$SANDBOX_HOME/.local/bin/custom-appimage-manager")"
assert_contains "$content" "manager-old-intact" "old binary intact"
leftovers="$(find "$SANDBOX_HOME/.local/bin" -name '.custom-appimage-manager.tmp.*' | wc -l)"
assert_eq "$leftovers" "0" "no tmp leftovers"
cleanup_sandbox

summary
