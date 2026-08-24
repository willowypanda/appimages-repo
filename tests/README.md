# Tests

Offline test suite for the manager, app management-scripts contract, and the
AdsPower build script. No real network access happens: `curl` and `bwrap` are
mocked via `tests/lib/mock-bin/`, and any request without a fixture route
fails the test.

## Running

```bash
tests/run-tests.sh                    # everything
tests/run-tests.sh manager            # exact group: manager|contract|apps-adspower|build
KEEP_TEST_TMP=1 tests/run-tests.sh    # keep sandbox dirs for debugging
```

The runner records the initial Git content snapshot (tracked hashes + untracked files) and fails if tests change anything.

## Layout

```text
tests/
  run-tests.sh              entry point; group filter; repo-cleanliness guard
  lib/lib.sh                sandbox (fake HOME/XDG/TMPDIR/PATH) + assertions
  lib/mock-bin/             curl (fixture-routed), bwrap (argv-recording), dpkg-deb
  fixtures/mock-curl/       routes file + response payloads for mock curl
  manager/                  custom-appimage-manager CLI/security/update-all/self-update
  contract/                 executable "Adding another app" contract (any app)
  apps/adspower/config.sh   per-app knobs consumed by the contract suite
  apps/adspower/run.bash    adspower-specific extras (runs contract suite too)
  build/test-build.bash     build-appimage.sh with mocked appimagetool/dpkg-deb
```

## Contract testing a new app

1. Add the app's `management-scripts/` under the repo root.
2. Create `tests/apps/<name>/config.sh` with its knobs:

```bash
APP_NAME="wechat"
SCRIPTS_SUBDIR="wechat/management-scripts"
FAKE_APPIMAGE_NAME='wechat-9.9.9-x86_64.AppImage'
FAKE_RELEASE_TAG="wechat-v9.9.9-0000000"
APP_DATA_DIRNAME="wechat-appimage"
SHORTCUT_PREFIX="wechat-appimage-"
```

3. Run `APP_CONFIG=tests/apps/wechat/config.sh tests/contract/test-contract.bash`.

The contract suite checks: required scripts exist/executable/bash -n clean;
run creates an isolated 0700 instance HOME and rejects bad instance names;
shortcut create/list/delete/sync semantics with absolute Exec paths;
uninstall keeps instance data unless confirmed; install is idempotent via
the release marker and never re-downloads when current.

## Notes

- The build suite mocks `appimagetool` to mimic real behavior: output is
  named from the desktop entry (`AdsPower-x86_64.AppImage`), NOT the
  versioned name — build-appimage.sh must rename it.
- CI runs this suite in `.github/workflows/test.yml`.
