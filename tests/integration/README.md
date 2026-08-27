## Running the install/uninstall audit

For verifying that `install` and `uninstall` only touch the documented paths
(per app directory, instance data, optional shared appimagetool cache),
there is a manual end-to-end audit:

```bash
sudo bash tests/integration/run-audit.sh                         # all four apps
sudo bash tests/integration/run-audit.sh adspower                # one app
sudo bash tests/integration/run-audit.sh baidunetdisk             # one app
sudo bash tests/integration/run-audit.sh tencentqq                # one app
sudo bash tests/integration/run-audit.sh wechat                  # one app
```

Requirements (all must be present on the running system):

- `bwrap`, `dpkg-deb`, `fakeroot`, `curl`, `python3`, `mount`, `umount`,
  `unshare`
- root (the script enters a private mount namespace, then bind-mounts shadow
  dirs over the target user's home, `/tmp`, and `/var/cache`; the host mounts
  are never replaced globally) — if `fakeroot` is missing, install it with
  `sudo apt install fakeroot` before running the audit.
- network access to `github.com` and `api.github.com` (real adspower deb is
  ~325MB; appimagetool is downloaded automatically)

Supported applications:

- `adspower`: real `.deb` download/repack/install/uninstall path;
- `wechat`: official rolling AppImage download path;
- `baidunetdisk`: versioned `.deb` download and local `.deb` to AppImage repack path. The upstream executable is nested at `/opt/baidunetdisk/baidunetdisk`; the audit covers this nested layout.
- `tencentqq`: official AppImage path, including `pcConfig.json` and signed-URL exchange.

What the script does:

1. Creates `/var/tmp/appimages-audit/run-<ts>-<pid>/` with shadow dirs.
2. Bind-mounts those shadows over the real paths (auto-unmounted on exit).
3. Snapshots files, runs `custom-appimage-manager app <app> install` under
   `fakeroot`.
4. Diffs the snapshot, rejects any file outside the documented whitelist
   (app directory, `~/.local/share/<app>-appimage/`, `.desktop` shortcuts,
   `~/.cache/appimages-repo/` for the shared appimagetool).
5. Runs `... uninstall` and re-snapshots, rejects any residual file
   except the documented retained appimagetool cache
   (see `docs/shared-cache-policy.md`).
6. Prints a pure-text report and the audit artifacts path.

This script is **deliberately not wired into CI** — it requires root, network,
and minutes of real downloads. Run it manually after any change to install
or uninstall logic, or when adding a new app.

If you ever want to run it from CI (not recommended): it intentionally does
NOT auto-skip; if root or bwrap is missing it fails fast with a clear error
so a misconfiguration is visible.
