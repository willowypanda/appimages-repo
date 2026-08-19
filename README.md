# appimages-repo

AGPL-3.0 project for building and publishing portable AppImages.

Current application:

```text
adspower/
```

## Build AdsPower locally

Install the Debian extraction tools and AppImage prerequisites:

```bash
sudo apt update
sudo apt install -y dpkg-dev curl python3 file
```

Build:

```bash
cd adspower
./download-latest.sh
./build-appimage.sh
```

The local output is named:

```text
adspower-<version>-x86_64.AppImage
```

## Run with an isolated instance

Install bubblewrap:

```bash
sudo apt install -y bubblewrap
```

Run separate AdsPower instances with separate data directories:

```bash
cd adspower
./run-sandboxed.sh --instance work --appimage ./adspower-8.7.23-x86_64.AppImage
./run-sandboxed.sh --instance personal --appimage ./adspower-8.7.23-x86_64.AppImage
```

Instance data is stored under:

```text
~/.local/share/adspower-appimage/instances/work/
~/.local/share/adspower-appimage/instances/personal/
```

The host `~/Downloads` directory is mounted read-write inside each instance as its `~/Downloads`. In bubblewrap mode, the host root filesystem is not mounted wholesale; only Electron runtime directories, required system files, graphics/audio sockets, `/dev/dri`, the instance HOME, and `~/Downloads` are exposed.

The launcher uses bubblewrap with an explicit filesystem allowlist. Select it explicitly with:

```bash
./run-sandboxed.sh --bwrap --instance work --appimage ./adspower-8.7.23-x86_64.AppImage
```

Bubblewrap is required; Firejail is not supported.

This is process/filesystem isolation similar in purpose to Flatpak, but it is not the same security model. Electron's internal sandbox remains disabled for AdsPower compatibility, as in the tested Flatpak package.

## GitHub Actions

`.github/workflows/build-adspower-appimage.yml`:

1. Downloads the latest AdsPower Linux x64 `.deb`;
2. Builds the AppImage;
3. Renames it to `adspower-<version>-<commit-hash>.AppImage`;
4. Generates a SHA256 checksum;
5. Creates a GitHub Release.

The release tag is:

```text
adspower-v<version>-<commit-hash>
```

The commit hash is the seven-character hash of the workflow's source commit.

## License

This project is licensed under the GNU Affero General Public License, version 3 or later. AdsPower itself is proprietary software distributed by its vendor; this repository contains packaging and launcher code only.
