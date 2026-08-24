#!/usr/bin/env bash
# Build script tests. Mock dpkg-deb and appimagetool so no real download or
# build happens; the mock appimagetool mimics REAL behavior: it derives its
# output name from the AppDir's .desktop file (e.g. "AdsPower-x86_64.AppImage"),
# NOT from any VERSION variable in build-appimage.sh.
set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
. "$LIB/lib.sh"

new_build_sandbox() {
  mk_sandbox; use_sandbox_env
  # Copy the adspower dir (scripts only) into sandbox as project dir.
  PROJ="$SANDBOX/adspower"
  mkdir -p "$PROJ"
  cp "$REPO_DIR/adspower/build-appimage.sh" "$PROJ/"
  chmod +x "$PROJ/build-appimage.sh"
  # Mock dpkg-deb is already on PATH via sandbox bin.
  # Mock appimagetool placed where build-appimage.sh expects it ($PROJ), so
  # its curl download path is skipped.
  cat > "$SANDBOX/bin/appimagetool-x86_64.AppImage" <<'MOCK'
#!/usr/bin/env bash
# Real appimagetool names output from the desktop entry inside AppDir.
appdir="${@: -1}"
desktop="$(find "$appdir" -maxdepth 1 -name '*.desktop' | head -1)"
name="$(grep '^Name=' "$desktop" | head -1 | cut -d= -f2 | tr ' ' '_')"
output="${name}-x86_64.AppImage"
echo "$output"
touch "$(dirname "$appdir")/$output"
exit 0
MOCK
  chmod +x "$SANDBOX/bin/appimagetool-x86_64.AppImage"
  cp "$SANDBOX/bin/appimagetool-x86_64.AppImage" "$PROJ/appimagetool-x86_64.AppImage"
  # A fake deb for dpkg-deb mock.
  mkdir -p "$PROJ/deb_download"
  : > "$PROJ/deb_download/AdsPower-Global-9.9.9-x64.deb"
  # The mock appimagetool IS the tool (no download needed): pre-create it
  # executable so build-appimage.sh skips its curl download.
  # (already written to $SANDBOX/bin/appimagetool-x86_64.AppImage)
}

t build-renames-tool-output-to-versioned-name -- true
new_build_sandbox
out="$(cd "$PROJ" && bash build-appimage.sh 2>&1)"; rc=$?
assert_eq "$rc" "0" "build rc: $out"
assert_file_exists "$PROJ/adspower-9.9.9-x86_64.AppImage"
cleanup_sandbox

t build-removes-stale-appimages-first -- true
new_build_sandbox
echo stale > "$PROJ/adspower-8.0.0-x86_64.AppImage"
out="$(cd "$PROJ" && bash build-appimage.sh 2>&1)"; rc=$?
assert_eq "$rc" "0" "build rc: $out"
assert_no_file "$PROJ/adspower-8.0.0-x86_64.AppImage"
assert_file_exists "$PROJ/adspower-9.9.9-x86_64.AppImage"
cleanup_sandbox

t build-rejects-two-deb-args -- true
new_build_sandbox
out="$(cd "$PROJ" && bash build-appimage.sh a.deb b.deb 2>&1)"; rc=$?
assert_eq "$rc" "2" "two debs rejected"
cleanup_sandbox

t build-rejects-options -- true
new_build_sandbox
out="$(cd "$PROJ" && bash build-appimage.sh --flag 2>&1)"; rc=$?
assert_eq "$rc" "2" "options rejected"
cleanup_sandbox

t build-no-deb-found-fails -- true
new_build_sandbox
rm -rf "$PROJ/deb_download"
out="$(cd "$PROJ" && bash build-appimage.sh 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then _pass; else _fail "should fail without deb"; fi
assert_contains "$out" "No .deb found" "error message"
cleanup_sandbox

t ci-build-output-name-matches-build-script -- true
# The CI expects adspower-${VERSION}-x86_64.AppImage to exist after the build;
# assert the build script really produces that name pattern.
new_build_sandbox
cd "$PROJ" && bash build-appimage.sh >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "build rc"
found="$(find "$PROJ" -maxdepth 1 -type f -name 'adspower-*-x86_64.AppImage' | wc -l)"
assert_eq "$found" "1" "exactly one versioned AppImage produced"
cleanup_sandbox

summary
