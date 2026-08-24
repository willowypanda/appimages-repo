#!/usr/bin/env bash
# Test entry point.
#
#   tests/run-tests.sh [group|test-name ...]
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
want() {
  [ "${#FILTERS[@]}" -eq 0 ] && return 0
  local f
  for f in "${FILTERS[@]}"; do
    [[ "$1" == *"$f"* ]] && return 0
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

# Repo must be clean before and after: tests must never modify it.
dirty() { [ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=normal)" ]; }
if dirty; then
  echo "*** ERROR: repo is dirty before running tests; commit or stash first." >&2
  git -C "$REPO_DIR" status --porcelain >&2
  exit 2
fi

run_file manager      "$TESTS_DIR/manager/test-manager.bash"
run_file contract     "$TESTS_DIR/contract/test-contract.bash"
run_file apps-adspower "$TESTS_DIR/apps/adspower/run.bash"
run_file build        "$TESTS_DIR/build/test-build.bash"

if dirty; then
  echo "*** FAIL: tests polluted the repository:" >&2
  git -C "$REPO_DIR" status --porcelain >&2
  OVERALL_FAIL=1
fi

echo "----------------------------------------"
if [ "$OVERALL_FAIL" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "SOME SUITES FAILED"
fi
exit "$OVERALL_FAIL"
