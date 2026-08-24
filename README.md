# appimages-repo

AGPL-3.0 project for building, publishing, and managing portable AppImages.

Current application:

```text
adspower/
wechat/
baidunetdisk/
```

## Install the common manager

The root-level `custom-appimage-manager` installs itself to `~/.local/bin`:

```bash
./custom-appimage-manager install
```

Make sure `~/.local/bin` is on `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

The manager can update itself from the latest `main` branch version:

```bash
custom-appimage-manager self-update
```

Update every installed app:

```bash
custom-appimage-manager update-all
```

This finds every app directory under `~/CustomAppimages` and runs its app-specific `management-scripts/update` script. If no apps are installed, it exits successfully without doing anything.

If any app fails to update, the remaining apps are still updated, and the command exits non-zero at the end listing the failed apps.

The manager downloads app-specific management scripts from:

```text
<repository>/<appname>/management-scripts/
```

Every app must provide at least:

```text
run-sandboxed.sh
run
check
update
install
uninstall
shortcut
```

## Install and manage Baidu Net Disk

Baidu Net Disk publishes versioned `.deb` packages on its CDN without a
version listing API. `baidunetdisk` discovers the latest version by probing
candidate URLs, downloads the .deb, and repackages it into a runnable
AppImage (appimagetool is fetched on first use):

```bash
custom-appimage-manager app baidunetdisk install   # download + repackage
custom-appimage-manager app baidunetdisk check     # check for newer version
custom-appimage-manager app baidunetdisk update    # refresh scripts + update
custom-appimage-manager app baidunetdisk run work  # named instance
```

Sandboxing matches the other apps: bubblewrap with an explicit allowlist,
per-instance HOME under `~/.local/share/baidunetdisk-appimage/instances/`, host
`~/Downloads` mounted read-write, and a per-instance fake machine-id.

## Install and manage WeChat

WeChat Linux ships an official AppImage at a rolling URL, so no .deb
conversion or GitHub release lookup is involved:

```bash
custom-appimage-manager app wechat install
```

The install is idempotent: upstream is identified by `Last-Modified` +
`Content-Length`, and the download is skipped when the file is unchanged.

```bash
custom-appimage-manager app wechat          # run default instance
custom-appimage-manager app wechat run work # named instance
custom-appimage-manager app wechat check    # check for updates
custom-appimage-manager app wechat update   # update, preserving instances
```

Like AdsPower, `update` first refreshes the management scripts from this
repository (continuing with local copies on failure), then updates the
AppImage.

Sandboxing matches AdsPower: bubblewrap with an explicit allowlist, per-
instance HOME under `~/.local/share/wechat-appimage/instances/`, and the
host `~/Downloads` mounted read-write as the instance's `~/Downloads`.

## Install and manage AdsPower

Install the latest AppImage and the AdsPower management scripts:

```bash
custom-appimage-manager app adspower install
```

This creates:

```text
~/CustomAppimages/adspower/
~/CustomAppimages/adspower/management-scripts/
```

The AppImage is downloaded from the latest GitHub Release and stored inside the app directory. Installation is idempotent: repeating the command does not download the same release again.

Run the default instance:

```bash
custom-appimage-manager app adspower
```

Run a named instance:

```bash
custom-appimage-manager app adspower run work
```

Because AdsPower is currently the only installed app, this shorthand also works:

```bash
custom-appimage-manager run work
```

Arguments after the script name are passed to that app's script:

```bash
custom-appimage-manager app adspower run work --some-app-argument
```

## App-specific management commands

Check for a newer AppImage or newer release metadata:

```bash
custom-appimage-manager app adspower check
```

Update the AppImage and refresh all management scripts:

```bash
custom-appimage-manager app adspower update
```

The update operation is idempotent. `update` works in two phases:

1. **Refresh management scripts** from this repository (fetched into a
   staging directory, validated, then swapped in atomically). If the
   refresh fails — e.g. no network — a warning is printed and the update
   continues with the existing local scripts.
2. **Update the AppImage** using the (now current) install script, which is
   idempotent and skips the download when the installed version already
   matches the latest release.

Instance data is never touched by either phase.

Uninstall the local AppImage and app directory contents:

```bash
custom-appimage-manager app adspower uninstall
```

The uninstall script removes the app's local AppImage, release marker, and desktop shortcuts. It asks before removing:

```text
~/.local/share/adspower-appimage/
```

Instance data is kept by default.

## Shortcuts

List AdsPower shortcuts:

```bash
custom-appimage-manager app adspower shortcut list
```

Create a shortcut for an instance:

```bash
custom-appimage-manager app adspower shortcut create work
```

This creates:

```text
~/.local/share/applications/adspower-appimage-work.desktop
```

The desktop entry runs:

```text
~/.local/bin/custom-appimage-manager run work
```

If the shortcut already exists, the command only reports it and does not overwrite it.

Delete a shortcut:

```bash
custom-appimage-manager app adspower shortcut delete work
```

Synchronize shortcuts with existing instance directories:

```bash
custom-appimage-manager app adspower shortcut sync
```

The convenience form below uses the only installed app:

```bash
custom-appimage-manager app shortcut sync
```

## AppImage build

Install local build dependencies:

```bash
sudo apt update
sudo apt install -y dpkg-dev curl python3 file
```

Build manually:

```bash
cd adspower
./download-latest.sh
./build-appimage.sh
```

The local output is named:

```text
adspower-<version>-x86_64.AppImage
```

## Sandboxing and instances

Install bubblewrap:

```bash
sudo apt install -y bubblewrap
```

AdsPower is run through bubblewrap only. Firejail is not supported.

Each instance has separate configuration, cache, profile, and HOME data:

```text
~/.local/share/adspower-appimage/instances/work/
~/.local/share/adspower-appimage/instances/personal/
```

The host `~/Downloads` directory is mounted read-write inside every instance as its `~/Downloads`.

The bubblewrap launcher does not bind the host root filesystem wholesale. It exposes an explicit allowlist of Electron runtime directories, selected system files, graphics/audio sockets, `/dev/dri`, basic device nodes, the instance HOME, and `~/Downloads`.

The AppImage is always run with:

```text
--appimage-extract-and-run
```

so FUSE is not required.

This isolation is similar in purpose to Flatpak, but is not identical. AdsPower's internal Electron sandbox remains disabled for compatibility.

## GitHub Actions

`.github/workflows/build-adspower-appimage.yml`:

1. Downloads the latest AdsPower Linux x64 `.deb`;
2. Builds the AppImage;
3. Renames it to `adspower-<version>-<commit-hash>.AppImage`;
4. Generates a SHA256 checksum;
5. Creates or updates a GitHub Release.

Release tag format:

```text
adspower-v<version>-<commit-hash>
```

## Adding another app

For a new app named `wechat`:

```text
wechat/
  management-scripts/
    run-sandboxed.sh
    run
    check
    update
    install
    uninstall
    shortcut
```

The app's `install` script must:

- download the latest AppImage from that app's GitHub Release;
- store it under `~/CustomAppimages/wechat/`;
- be safe to run repeatedly;
- preserve instance data during updates;
- use the app's own AppImage naming and release logic.

The common manager automatically downloads the app's `management-scripts` directory and dispatches commands to the app-specific scripts.

New apps should also add a test config (`tests/apps/<name>/config.sh`) and pass the contract suite — see `tests/README.md`.

## Command contract

```text
custom-appimage-manager install
custom-appimage-manager self-update
custom-appimage-manager app APP install
custom-appimage-manager app APP
custom-appimage-manager app APP SCRIPT [ARGS...]
custom-appimage-manager run [INSTANCE] [ARGS...]
custom-appimage-manager shortcut APP [list|create|delete|sync] [INSTANCE]
```

If an app is not installed, the manager prints an installation hint instead of attempting to run its scripts.

## License

This repository's packaging and management code is licensed under AGPL-3.0-or-later. AdsPower itself is proprietary software distributed by its vendor; this repository contains packaging, sandbox launcher, and management code only.
