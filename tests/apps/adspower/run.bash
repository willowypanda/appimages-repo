#!/usr/bin/env bash
# Adspower-specific tests beyond the generic contract.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
. "$LIB/lib.sh"

run_contract_suite() {
  APP_CONFIG="$REPO_DIR/tests/apps/$1/config.sh" \
    bash "$REPO_DIR/tests/contract/test-contract.bash"
}

t adspower-passes-contract-suite -- true
out="$(run_contract_suite adspower 2>&1)"; rc=$?
assert_eq "$rc" "0" "contract suite rc: $out"
_pass

t launcher-bwrap-argv-has-explicit-allowlist -- true
mk_sandbox; use_sandbox_env
APP="$SANDBOX_HOME/CustomAppimages/adspower"
mkdir -p "$APP/management-scripts" "$SANDBOX/work"
cp -a "$REPO_DIR"/adspower/management-scripts/. "$APP/management-scripts/"
: > "$APP/adspower-1.0.0-x86_64.AppImage"
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
cd "$SANDBOX/work" && bash "$APP/management-scripts/run" default >/dev/null 2>&1; rc=$?
[ -f "$MOCK_BWRAP_LOG" ] || { _fail "bwrap not invoked (rc=$rc)"; cleanup_sandbox; continue; }
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
cp -a "$REPO_DIR"/adspower/management-scripts/. "$APP/management-scripts/"
: > "$APP/adspower-1.0.0-x86_64.AppImage"
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
cd "$SANDBOX/work" && bash "$APP/management-scripts/run" default >/dev/null 2>&1
expected_user="$(id -un)"
argv="$(tr '\0' '\n' < "$MOCK_BWRAP_LOG" | paste -sd ' ' -)"
assert_contains "$argv" "USER $expected_user" "USER fallback value in bwrap argv"
cleanup_sandbox

t launcher-and-shortcut-share-xdg-instance-root -- true
mk_sandbox; use_sandbox_env
APP="$SANDBOX_HOME/CustomAppimages/adspower"
mkdir -p "$APP/management-scripts"
cp -a "$REPO_DIR"/adspower/management-scripts/. "$APP/management-scripts/"
: > "$APP/adspower-1.0.0-x86_64.AppImage"
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
bash "$APP/management-scripts/run" work >/dev/null 2>&1
bash "$APP/management-scripts/shortcut" sync >/dev/null 2>&1
assert_file_exists "$XDG_DATA_HOME/applications/adspower-appimage-work.desktop"
cleanup_sandbox

# --- update script: refresh scripts first, then update the AppImage ---

setup_adspower_update_env() {
  mk_sandbox; use_sandbox_env
  APP="$SANDBOX_HOME/CustomAppimages/adspower"
  mkdir -p "$APP/management-scripts" "$APP/.release-tag.d"
  cp -a "$REPO_DIR"/adspower/management-scripts/. "$APP/management-scripts/"
  : > "$APP/adspower-9.9.9-x86_64.AppImage"
  printf 'adspower-v9.9.9-0000000\n' > "$APP/.release-tag"
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
  cat > "$MOCK_FIXTURES/scripts-list-adspower.json" <<'EOF'
[{"name":"run","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/run"},{"name":"check","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/check"},{"name":"update","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/update"},{"name":"install","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/install"},{"name":"uninstall","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/uninstall"},{"name":"shortcut","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/shortcut"},{"name":"run-sandboxed.sh","type":"file","download_url":"https://raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts/run-sandboxed.sh"}]
EOF
  printf 'contents/adspower/management-scripts\tscripts-list-adspower.json\n' > "$MOCK_FIXTURES/routes"
  printf 'raw.githubusercontent.com/willowypanda/appimages-repo/main/adspower/management-scripts\tempty\n' >> "$MOCK_FIXTURES/routes"
}

t adspower-update-refreshes-scripts-then-appimage -- true
setup_adspower_update_env
out="$(bash "$APP/management-scripts/update" 2>&1)"; rc=$?
assert_eq "$rc" "0" "update rc: $out"
assert_contains "$out" "Management scripts updated." "scripts refresh reported"
cleanup_sandbox

t adspower-update-proceeds-when-scripts-refresh-fails -- true
setup_adspower_update_env
rm -f "$MOCK_FIXTURES/routes"   # API unreachable -> refresh fails; install also fails, but update must not crash before warning
out="$(bash "$APP/management-scripts/update" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "install without routes should fail"; fi
assert_contains "$out" "Warning: could not refresh management scripts" "warning shown"
cleanup_sandbox

summary
