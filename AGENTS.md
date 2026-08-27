# AGENTS — guidance for AI agents and contributors

## Repository shape

- `custom-appimage-manager` is the generic entry point. Per-app behavior
  lives in each app's `management-scripts/`.
- Apps currently: `adspower/`, `wechat/`, `baidunetdisk/`, `tencentqq/`.
  Adding a new app means: copy the structure, write the 7 required scripts,
  add `tests/apps/<name>/config.sh` + `run.bash`, register the group in
  `tests/run-tests.sh`, update README. See `tests/README.md` for the full
  recipe.
- Tests live under `tests/`:
  - `tests/lib/`, `tests/manager/`, `tests/contract/`, `tests/build/`,
    `tests/apps/<name>/` — fully offline, no network, no root, CI-friendly.
    Run via `tests/run-tests.sh`.
  - `tests/integration/run-audit.sh` — manual end-to-end install/uninstall
    audit under `fakeroot` + private mount namespaces. It covers all four
    apps: `adspower`, `wechat`, `baidunetdisk`, and `tencentqq`. **Not** part
    of CI. See `tests/integration/README.md` and the README "End-to-end
    install/uninstall audit" section.

## Things to know before changing scripts

- `update` for every app does two phases: first refreshes management
  scripts from this repo (warning + continue on failure), then runs the
  app-specific install. Don't bypass this.
- The appimagetool is shared via `~/.cache/appimages-repo/appimagetool/`
  with a 30-day freshness window. Uninstall scripts intentionally do NOT
  delete it (multiple apps may share it). See `docs/shared-cache-policy.md`.
- `tests/lib/mock-bin/curl` is the only network stub in the test suite.
  All production scripts route their HTTP through it during tests; if
  you add a script that uses a new URL pattern, add a matching route in
  the per-app `run.bash` setup.
- Bubblewrap argv is recorded by `tests/lib/mock-bin/bwrap` to
  `$MOCK_BWRAP_LOG` (NUL-delimited). Use `mapfile -d '' -t` to parse;
  do not rely on the previous string-based heuristics — they're gone.

## CI hygiene

- `tests/run-tests.sh` must stay green on every commit. It contains a
  repo-content snapshot guard: tests must not write to the repository.
- Do NOT add `tests/integration/run-audit.sh` to any CI workflow. The
  script intentionally fails fast if root or bwrap is missing, so an
  accidental CI inclusion surfaces immediately rather than silently
  passing.
- If you find yourself tempted to `set -u` only at the top of a script,
  remember that test files source `tests/lib/lib.sh` which uses
  `set -uo pipefail` (no `-e`) — every command that can fail should
  handle errors explicitly.
