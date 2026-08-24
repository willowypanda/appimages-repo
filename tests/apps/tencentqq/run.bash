#!/usr/bin/env bash
# Tencent QQ-specific tests beyond the generic contract.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
. "$LIB/lib.sh"

run_contract_suite() {
  APP_CONFIG="$REPO_DIR/tests/apps/$1/config.sh" \
    bash "$REPO_DIR/tests/contract/test-contract.bash"
}

t tencentqq-passes-contract-suite -- true
out="$(run_contract_suite tencentqq 2>&1)"; rc=$?
assert_eq "$rc" "0" "contract suite rc: $out"
_pass

new_qq_app() {
  mk_sandbox; use_sandbox_env
  APP="$SANDBOX_HOME/CustomAppimages/tencentqq"
  mkdir -p "$APP/management-scripts" "$SANDBOX/bin" "$SANDBOX/work"
  cp -a "$REPO_DIR"/tencentqq/management-scripts/. "$APP/management-scripts/"
  : > "$APP/QQ-x86_64.AppImage"
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
  # pcConfig.json fixture: version + unsigned appimage URL
  cat > "$MOCK_FIXTURES/pcConfig.json" <<'EOF'
{"Linux":{"version":"3.2.32","x64DownloadUrl":{"appimage":"https://qqdl.gtimg.cn/qqfile/QQNTV2/x/AppImage"}}}
EOF
  cat > "$MOCK_FIXTURES/routes" <<'EOF'
pcConfig.json	pcConfig.json
im.qq.com/http2rpc	sign-response.json
EOF
  cat > "$MOCK_FIXTURES/sign-response.json" <<'EOF'
{"data":{"url":"https://qqdl.gtimg.cn/signed/QQ.AppImage?sign=abc"}}
EOF
  : > "$MOCK_FIXTURES/appimage-fixture"
  printf 'raw.githubusercontent.com/willowypanda/appimages-repo/main/tencentqq/management-scripts\tappimage-fixture\n' >> "$MOCK_FIXTURES/routes"
  printf 'qqdl.gtimg.cn\tappimage-fixture\n' >> "$MOCK_FIXTURES/routes"
}

t tencentqq-latest-release-parses-config -- true
new_qq_app
out="$(bash -c 'source '"$APP"'/management-scripts/_common.sh; latest_release')"; rc=$?
assert_eq "$rc" "0" "latest_release rc: $out"
assert_contains "$out" "3.2.32" "version from pcConfig"
grep -q "GET https://qq-web.cdn-go.cn/im.qq.com_new/latest/rainbow/pcConfig.json" "$MOCK_CURL_LOG" \
  && _pass || _fail "did not fetch live config URL"
cleanup_sandbox

t tencentqq-signed-url-flow -- true
new_qq_app
# Full install with stale marker: config -> sign -> download signed URL.
printf 'stale\n' > "$APP/.release-tag"
I="$APP/management-scripts/install"
out="$(bash "$I" 2>&1)"; rc=$?
assert_eq "$rc" "0" "install rc: $out"
assert_file_exists "$APP/QQ-x86_64.AppImage"
grep -q "GetSign" "$MOCK_CURL_LOG" && _pass || _fail "sign RPC not called"
grep -q "GET https://qqdl.gtimg.cn/signed/QQ.AppImage" "$MOCK_CURL_LOG" && _pass || _fail "did not download via signed URL"
assert_contains "$(cat "$APP/.release-tag")" "3.2.32" "marker updated"
cleanup_sandbox

summary
