#!/usr/bin/env bash
# WeChat-specific tests beyond the generic contract.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
. "$LIB/lib.sh"

run_contract_suite() {
  APP_CONFIG="$REPO_DIR/tests/apps/$1/config.sh" \
    bash "$REPO_DIR/tests/contract/test-contract.bash"
}

t wechat-passes-contract-suite -- true
out="$(run_contract_suite wechat 2>&1)"; rc=$?
assert_eq "$rc" "0" "contract suite rc: $out"
_pass

new_wechat_app() {
  mk_sandbox; use_sandbox_env
  APP="$SANDBOX_HOME/CustomAppimages/wechat"
  mkdir -p "$APP/management-scripts" "$SANDBOX/bin" "$SANDBOX/work"
  cp -a "$REPO_DIR"/wechat/management-scripts/. "$APP/management-scripts/"
  cp "$REPO_DIR"/wechat/management-scripts/.launcher-template.sh "$APP/management-scripts/"
  : > "$APP/WeChatLinux_x86_64.AppImage"
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
}

t wechat-install-downloads-from-official-url -- true
new_wechat_app
I="$APP/management-scripts/install"
printf 'FAKE-APPIMAGE\n' > "$MOCK_FIXTURES/appimage-fixture"
printf 'old\n' > "$APP/.release-tag"
out="$(bash "$I" 2>&1)"; rc=$?
assert_eq "$rc" "0" "install rc: $out"
assert_file_exists "$APP/WeChatLinux_x86_64.AppImage"
assert_contains "$(cat "$APP/WeChatLinux_x86_64.AppImage")" "FAKE-APPIMAGE" "content from official URL"
grep -q "GET https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage" "$MOCK_CURL_LOG" \
  && _pass || _fail "download did not hit the official URL"
cleanup_sandbox

t wechat-check-detects-update -- true
new_wechat_app
C="$APP/management-scripts/check"
printf 'stale\n' > "$APP/.release-tag"
out="$(bash "$C" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _fail "check rc=$rc: $out"; fi
assert_contains "$out" "Update available" "update detection"
cleanup_sandbox

t wechat-launcher-binds-downloads-rw -- true
new_wechat_app
export MOCK_BWRAP_LOG="$SANDBOX/bwrap.log"
cd "$SANDBOX/work" && bash "$APP/management-scripts/run" main >/dev/null 2>&1
mapfile -d '' -t argv < "$MOCK_BWRAP_LOG"
found=0
for ((i=0; i+2<${#argv[@]}; i++)); do
  if [ "${argv[$i]}" = "--bind" ] && [ "${argv[$((i+2))]}" = "$HOME/Downloads" ]; then found=1; fi
done
if [ "$found" = 1 ]; then _pass; else _fail "~/Downloads not mounted read-write into sandbox HOME"; fi
cleanup_sandbox

# --- update script: refresh scripts via manager, fall back to local install ---

setup_update_env() {
  new_wechat_app
  U="$APP/management-scripts/update"
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
  : > "$MOCK_FIXTURES/appimage-fixture"
  printf 'dldir1v6.qq.com\tappimage-fixture\n' > "$MOCK_FIXTURES/routes"
}

install_stub_manager() { # records invocation
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/custom-appimage-manager" <<STUB
#!/usr/bin/env bash
echo "MANAGER-INVOKED \$*" >> "$SANDBOX/manager.log"
# Simulate the manager contract: refresh scripts (touch a marker), then run install.
echo refreshed > "$APP/management-scripts/.refreshed-by-manager"
bash "$APP/management-scripts/install" "\$@"
STUB
  chmod +x "$HOME/.local/bin/custom-appimage-manager"
}

t wechat-update-routes-through-manager-when-available -- true
setup_update_env
install_stub_manager
out="$(printf 'old\n' > "$APP/.release-tag"; bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "update rc via manager: $out"
assert_contains "$(cat "$SANDBOX/manager.log")" "app wechat install" "manager invoked with install"
assert_file_exists "$APP/management-scripts/.refreshed-by-manager"
cleanup_sandbox

t wechat-update-falls-back-to-local-install-without-manager -- true
setup_update_env
rm -f "$HOME/.local/bin/custom-appimage-manager"
out="$(printf 'old\n' > "$APP/.release-tag"; bash "$U" 2>&1)"; rc=$?
assert_eq "$rc" "0" "fallback update rc: $out"
assert_file_exists "$APP/WeChatLinux_x86_64.AppImage"
if [ -e "$SANDBOX/manager.log" ]; then _fail "manager path used although absent"; else _pass; fi
cleanup_sandbox

summary
