# tests/lib.sh — shared test helpers for the appimages-repo test suite.
# Source this file from test files: . "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
CURRENT_TEST=""
SANDBOX=""
ORIGINAL_HOME="${HOME:-}"
ORIGINAL_PATH="$PATH"

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

# Create an isolated sandbox: fake HOME, XDG dirs, TMPDIR and a PATH whose
# first entry is the mock bin dir. Every test MUST run inside one.
mk_sandbox() {
  local parent="${TMPDIR:-/tmp}"
  [ -d "$parent" ] || parent=/tmp
  SANDBOX="$(mktemp -d "$parent/appimages-test.XXXXXX")"
  SANDBOX_HOME="$SANDBOX/home"
  mkdir -p "$SANDBOX_HOME" \
           "$SANDBOX/xdg/config" "$SANDBOX/xdg/data" "$SANDBOX/xdg/cache" \
           "$SANDBOX/xdg/runtime" "$SANDBOX/tmp" \
           "$SANDBOX/bin" "$SANDBOX/work" "$SANDBOX/fixtures/mock-curl"
  chmod 700 "$SANDBOX/xdg/runtime"
  # Mock commands dir; tests may add stubs here. curl is mocked to fail by
  # default (no real network); bwrap is mocked to record its argv.
  cp -r "$TESTS_DIR/lib/mock-bin/." "$SANDBOX/bin/"
  chmod +x "$SANDBOX/bin/"* 2>/dev/null || true
  # Each test gets a private fixture copy so route changes cannot mutate the
  # repository or race another test process.
  cp -r "$TESTS_DIR/fixtures/mock-curl/." "$SANDBOX/fixtures/mock-curl/" 2>/dev/null || true
  MOCK_FIXTURES="$SANDBOX/fixtures/mock-curl"
  export MOCK_FIXTURES
}

# Apply the sandbox environment. Called after mk_sandbox, before running the
# system under test.
use_sandbox_env() {
  HOME="$SANDBOX_HOME"
  XDG_CONFIG_HOME="$SANDBOX/xdg/config"
  XDG_DATA_HOME="$SANDBOX/xdg/data"
  XDG_CACHE_HOME="$SANDBOX/xdg/cache"
  XDG_RUNTIME_DIR="$SANDBOX/xdg/runtime"
  TMPDIR="$SANDBOX/tmp"
  PATH="$SANDBOX/bin:$ORIGINAL_PATH"
  export HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR PATH MOCK_FIXTURES
  umask 077
}

cleanup_sandbox() {
  # Never remove the process's current working directory; doing so causes
  # later commands to emit getcwd failures and can invalidate relative paths.
  cd "$REPO_DIR" || return 1
  if [ -n "${KEEP_TEST_TMP:-}" ] && [ -n "${SANDBOX:-}" ]; then
    echo "KEEP_TEST_TMP set; sandbox kept at $SANDBOX" >&2
    return
  fi
  if [ -n "${SANDBOX:-}" ]; then
    case "$SANDBOX" in
      */appimages-test.*) rm -rf "$SANDBOX" ;;
      *) echo "Refusing to remove unexpected sandbox path: $SANDBOX" >&2; return 1 ;;
    esac
  fi
  SANDBOX=""
  HOME="$ORIGINAL_HOME"
  PATH="$ORIGINAL_PATH"
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR
  unset MOCK_BWRAP_LOG MOCK_BWRAP_RUN_TARGET MOCK_CURL_LOG MOCK_FIXTURES
  export HOME PATH
}

# Run a command inside the sandbox env.
in_sandbox() { "$@"; }

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL [$CURRENT_TEST] $*" >&2
}
_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
_skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); echo "SKIP [$CURRENT_TEST] $*" >&2; }

assert_eq() { # actual expected [label]
  local actual="$1" expected="$2" label="${3:-value}"
  if [ "$actual" = "$expected" ]; then _pass; else _fail "$label: got '$actual', want '$expected'"; fi
}
assert_rc() { # expected_rc cmd...
  local expected="$1"; shift
  local rc; "$@" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" "$expected" "exit code of: $*"
}
assert_file_exists() {
  if [ -e "$1" ]; then _pass; else _fail "file does not exist: $1"; fi
}
assert_no_file() {
  if [ ! -e "$1" ]; then _pass; else _fail "file unexpectedly exists: $1"; fi
}
assert_contains() { # haystack needle [label]
  case "$1" in *"$2"*) _pass ;; *) _fail "${3:-string} does not contain '$2': '$1'" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) _fail "${3:-string} must not contain '$2'" ;; *) _pass ;; esac
}
assert_output_contains() { # needle cmd...  — runs cmd, checks combined output
  local needle="$1"; shift
  local out; out="$("$@" 2>&1)"
  assert_contains "$out" "$needle" "output of: $*"
}
assert_empty_dir() {
  if [ ! -d "$1" ]; then _fail "not a directory: $1"; return; fi
  if [ -z "$(ls -A "$1")" ]; then _pass; else _fail "directory not empty: $1 ($(ls -A "$1"))"; fi
}

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

t() { # t NAME [-- ignored-legacy-args...]
  # Tests perform their actions explicitly after setting the label. Earlier
  # versions tried to execute the literal `--` argument here; the result was
  # ignored, so that code provided no verification and was misleading.
  CURRENT_TEST="$1"
}

summary() {
  echo "----------------------------------------"
  echo "passed=$PASS_COUNT failed=$FAIL_COUNT skipped=$SKIP_COUNT"
  if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
  exit 0
}
