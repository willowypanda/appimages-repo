#!/usr/bin/env bash
# Test entry point.
#
#   tests/run-tests.sh [group ...]
#
# Groups: manager contract apps-adspower build
# Environment:
#   KEEP_TEST_TMP=1   keep sandbox dirs for debugging
#   RUN_NETWORK_TESTS=1 also run tests that need real internet (default off)
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export MOCK_FIXTURES="${MOCK_FIXTURES:-$TESTS_DIR/fixtures/mock-curl}"

FILTERS=("$@")
VALID_GROUPS=(manager contract apps-adspower apps-wechat apps-baidunetdisk apps-tencentqq build)
for requested in "${FILTERS[@]}"; do
  valid=0
  for group in "${VALID_GROUPS[@]}"; do
    [ "$requested" = "$group" ] && valid=1
  done
  if [ "$valid" -ne 1 ]; then
    echo "*** ERROR: unknown test group: $requested" >&2
    exit 2
  fi
done

want() {
  [ "${#FILTERS[@]}" -eq 0 ] && return 0
  local f
  for f in "${FILTERS[@]}"; do
    [ "$1" = "$f" ] && return 0
  done
  return 1
}

run_file() { # run_file <label> <file>
  local label="$1" file="$2"
  want "$label" || return 0
  echo "=== $label ==="
  bash "$file"; local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "*** GROUP FAILED: $label (rc=$rc)" >&2
    OVERALL_FAIL=1
  fi
}

OVERALL_FAIL=0

# Tests may run while code is being developed. Snapshot the full content
# state (tracked hashes + untracked paths + untracked hashes) and require an
# identical snapshot afterwards; porcelain alone cannot detect content edits
# to files that were already modified before the run.
repo_snapshot() {
  (
    cd "$REPO_DIR"
    git status --porcelain=v1 --untracked-files=all
    git ls-files -z | sort -z | xargs -0 sha256sum 2>/dev/null || true
    git ls-files -o --exclude-standard -z | sort -z | xargs -0 sha256sum 2>/dev/null || true
  )
}
BASELINE_SNAPSHOT="$(repo_snapshot)"

run_file manager      "$TESTS_DIR/manager/test-manager.bash"
run_file contract     "$TESTS_DIR/contract/test-contract.bash"
run_file apps-adspower "$TESTS_DIR/apps/adspower/run.bash"
run_file apps-wechat  "$TESTS_DIR/apps/wechat/run.bash"
run_file apps-baidunetdisk "$TESTS_DIR/apps/baidunetdisk/run.bash"
run_file apps-tencentqq "$TESTS_DIR/apps/tencentqq/run.bash"
run_file build        "$TESTS_DIR/build/test-build.bash"

FINAL_SNAPSHOT="$(repo_snapshot)"
if [ "$FINAL_SNAPSHOT" != "$BASELINE_SNAPSHOT" ]; then
  echo "*** FAIL: tests polluted the repository (status or content changed):" >&2
  diff -u <(printf '%s\n' "$BASELINE_SNAPSHOT") <(printf '%s\n' "$FINAL_SNAPSHOT") >&2 || true
  OVERALL_FAIL=1
fi

echo "----------------------------------------"
if [ "$OVERALL_FAIL" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "SOME SUITES FAILED"
fi
exit "$OVERALL_FAIL"
