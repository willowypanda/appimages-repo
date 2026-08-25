# 共享缓存与清理策略

## 涉及的共享数据

`ensure-appimagetool.sh`（各 app management-scripts 内的 vendored 副本）会把
appimagetool 正本存放在跨 app 共享的缓存目录：

```text
~/.cache/appimages-repo/appimagetool/appimagetool-x86_64.AppImage
```

各 app 目录内的 `.appimagetool-*.AppImage` 只是指向（或复制自）这个正本的
本地副本，供打包时使用。

## uninstall 时不删除缓存（有意为之）

所有 app 的 `uninstall` 脚本只清理两处：

1. app 自己的目录 `~/CustomAppimages/<app>/`（含其中的工具副本）；
2. 该 app 的实例数据目录 `~/.local/share/<app>-appimage/`
   （且删除前会询问确认，默认保留）。

**共享缓存正本不会被卸载删除**。理由：

- 缓存被多个 app 共享——卸载其中一个 app 不应影响其他 app 的打包能力；
- 体量很小（约 15MB），且位于 `~/.cache/` 下，符合 XDG 对"可随时清除的
  缓存"的定义；
- 代码对缓存缺失有防御：每次打包前都会检查并按需重新下载，因此手动清空
  缓存或被系统清理工具清除都不会导致功能损坏。

## 手动清理方式

全部 app 都卸载后，如需释放这约 15MB：

```bash
rm -rf ~/.cache/appimages-repo/appimagetool/
```

下次任意 app 执行 install 时会自动重新下载。

## 相关环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `TOOL_MAX_AGE_DAYS` | 30 | 工具超过该天数后下次使用时自动重新下载 |
| `FORCE_TOOL_REFRESH` | 0 | 设为 1 强制立即刷新（忽略年龄检查） |

## 验证记录（2026-08-24）

沙箱实验确认：卸载 baidunetdisk 后，app 目录被正确移除，
`~/.cache/appimages-repo/appimagetool/` 下的正本仍然存在。
