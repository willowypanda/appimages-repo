#!/usr/bin/env bash
# Adspower-specific tests beyond the generic contract.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
. "$LIB/lib.sh"

run_contract_suite() {
  APP_CONFIG="$REPO_DIR/tests/apps/adspower/config.sh" \
    bash "$REPO_DIR/tests/contract/test-contract.bash"
}

t adspower-passes-contract-suite -- true
out="$(run_contract_suite 2>&1)"; rc=$?
assert_eq "$rc" "0" "contract suite rc: $out"
_pass

t launcher-bwrap-argv-has-explicit-allowlist -- true
mk_sandbox; use_sandbox_env
APP="$SANDBOX_HOME/CustomAppimages/adspower"
mkdir -p "$APP/management-scripts" "$SANDBOX/work"
cp "$REPO_DIR"/adspower/management-scripts/* "$APP/management-scripts/"
: > "$APP/adspower-1.0.0-x86_64.AppImage"
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
cd "$SANDBOX/work" && bash "$APP/management-scripts/run" default >/dev/null 2>&1; rc=$?
[ -f "$MOCK_BWRAP_LOG" ] || { _fail "bwrap not invoked (rc=$rc)"; cleanup_sandbox; return 0; }
argv="$(tr '\0' '\n' < "$MOCK_BWRAP_LOG")"
assert_contains "$argv" "--appimage-extract-and-run" "FUSE-less execution"
assert_contains "$argv" "/opt/adspower.AppImage" "fixed read-only appimage path"
case "$argv" in
  *"--ro-bind / /"*) _fail "must not bind host root wholesale" ;;
  *) _pass ;;
esac
cleanup_sandbox

t launcher-user-fallback-recorded-in-argv -- true
mk_sandbox; use_sandbox_env
unset USER
APP="$SANDBOX_HOME/CustomAppimages/adspower"
mkdir -p "$APP/management-scripts" "$SANDBOX/work"
cp "$REPO_DIR"/adspower/management-scripts/* "$APP/management-scripts/"
: > "$APP/adspower-1.0.0-x86_64.AppImage"
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
cd "$SANDBOX/work" && bash "$APP/management-scripts/run" default >/dev/null 2>&1
expected_user="$(id -un)"
argv="$(tr '\0' '\n' < "$MOCK_BWRAP_LOG" | paste -sd ' ' -)"
assert_contains "$argv" "USER $expected_user" "USER fallback value in bwrap argv"
cleanup_sandbox

summary
