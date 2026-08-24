# Per-app test configuration — consumed by tests/contract/test-contract.bash
APP_NAME="wechat"
SCRIPTS_SUBDIR="wechat/management-scripts"
FAKE_APPIMAGE_NAME='WeChatLinux_x86_64.AppImage'
# WeChat upstream uses a rolling URL without versioned releases; the marker
# is "<last-modified>|<content-length>".
FAKE_RELEASE_TAG="GMT 14:06:47 2026|0"
APP_DATA_DIRNAME="wechat-appimage"
SHORTCUT_PREFIX="wechat-appimage-"
