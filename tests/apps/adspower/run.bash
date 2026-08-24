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
mapfile -d '' -t argv < "$MOCK_BWRAP_LOG"
has_arg() {
  local wanted="$1" arg
  for arg in "${argv[@]}"; do [ "$arg" = "$wanted" ] && return 0; done
  return 1
}
has_sequence() {
  local first="$1" second="$2" i
  for ((i=0; i+1<${#argv[@]}; i++)); do
    [ "${argv[$i]}" = "$first" ] && [ "${argv[$((i+1))]}" = "$second" ] && return 0
  done
  return 1
}
has_arg "--appimage-extract-and-run" && _pass || _fail "missing FUSE-less execution flag"
has_arg "/opt/adspower.AppImage" && _pass || _fail "missing fixed AppImage path"
# Reject ANY whole-root exposure regardless of bind type (ro, rw, or dev).
if has_sequence "--ro-bind" "/" || has_sequence "--bind" "/" || has_sequence "--dev-bind" "/"; then
  _fail "must not bind host root wholesale"
else
  _pass
fi
has_sequence "--bind" "$HOME/Downloads" && _pass || _fail "host Downloads not writable-bound"
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
