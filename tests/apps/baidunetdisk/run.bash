#!/usr/bin/env bash
# Baidu Net Disk-specific tests beyond the generic contract.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
. "$LIB/lib.sh"

run_contract_suite() {
  APP_CONFIG="$REPO_DIR/tests/apps/baidunetdisk/config.sh" \
    bash "$REPO_DIR/tests/contract/test-contract.bash"
}

# The upstream package keeps the executable at /opt/baidunetdisk/baidunetdisk;
# the installer must find nested binaries, not only top-level files.

t baidunetdisk-passes-contract-suite -- true
out="$(run_contract_suite baidunetdisk 2>&1)"; rc=$?
assert_eq "$rc" "0" "contract suite rc: $out"
_pass

new_baidunetdisk_app() {
  mk_sandbox; use_sandbox_env
  APP="$SANDBOX_HOME/CustomAppimages/baidunetdisk"
  mkdir -p "$APP/management-scripts" "$SANDBOX/bin" "$SANDBOX/work"
  cp -a "$REPO_DIR"/baidunetdisk/management-scripts/. "$APP/management-scripts/"
  : > "$APP/baidunetdisk-x86_64.AppImage"
  export MOCK_CURL_LOG="$SANDBOX/curl.log"
}

t baidunetdisk-latest-release-probes-candidates -- true
new_baidunetdisk_app
# Mock HEAD fixtures: 200 for existing versions, 404 header block otherwise.
printf 'HTTP/1.1 200 OK\r\nContent-Length: 189616700\r\n' > "$MOCK_FIXTURES/head-200"
printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n'   > "$MOCK_FIXTURES/head-404"
cat > "$MOCK_FIXTURES/routes" <<'EOF'
issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.8	head-200
issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.9	head-200
issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.10	head-200
issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.11	head-404
issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.12	head-404
EOF
out="$(bash -c 'source '"$APP"'/management-scripts/_common.sh; latest_release')"; rc=$?
assert_eq "$rc" "0" "latest_release rc: $out"
assert_contains "$out" "4.17.10" "probes upward and finds newest existing"
cleanup_sandbox

t baidunetdisk-check-compares-versions -- true
new_baidunetdisk_app
C="$APP/management-scripts/check"
printf '4.17.7\n' > "$APP/.release-tag"
printf 'HTTP/1.1 200 OK\r\nContent-Length: 189616700\r\n' > "$MOCK_FIXTURES/head-200"
cat > "$MOCK_FIXTURES/routes" <<'EOF'
issuecdn.baidupcs.com	head-200
EOF
out="$(bash "$C" 2>&1)"
assert_contains "$out" "Update available" "update detection"
cleanup_sandbox

summary
