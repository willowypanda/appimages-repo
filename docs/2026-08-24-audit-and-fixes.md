# 审计与修复记录 — 2026-08-24

对仓库全部脚本（根管理器、adspower 构建脚本、management-scripts、CI workflow）做了对照 README 的行为审计，并经过本地实验与独立子代理交叉复核。本文档记录发现、验证方法与修复内容。

## 发现总览

| 编号 | 问题 | 严重度 | 判定 |
|---|---|---|---|
| 1 | manager 未在文件操作前校验 app 名称，存在路径逃逸与目录外脚本执行 | 高 | 确认，已修复 |
| 2 | `shortcut sync` 查找 `adspower-appimage/` 一级目录而非 `instances/`，生成错误快捷方式 | 中 | 确认，已修复 |
| 3 | install 不校验 Release 附带的 `.sha256` | 中（加固） | 用户决定不修复 |
| 4 | 构建后用无排序的 `find -print -quit` 挑产物，可能选中旧版本；含来源不明的父目录兜底分支 | 低/中 | 确认，已修复 |
| 5 | self-update：RETURN trap 在失败退出时不清理 `/tmp` 临时文件；跨文件系统 mv 非原子 | 低 | 确认，已修复 |
| 6 | update-all 遇到单个失败即中断后续 app | 低 | 确认，已修复 |
| 7 | `${USER}` 无回退，`set -u` 下未定义时崩溃 | 低 | 确认，已修复 |
| 8 | check 把 install 脚本存在性混入"是否最新"判断，可误报 | 低 | 确认，已修复 |
| 9 | ENGINE 变量与 `--bwrap` 参数是死分支 | 代码质量 | 已简化 |
| 10 | 桌面 Exec 用裸命令名，依赖桌面会话 PATH 含 `~/.local/bin` | 条件性 | 已改为绝对路径 |
| H2(撤回) | "`--ro-bind` socket 导致无法连接" | — | 误报：只读 bind mount 不阻止对已有 Unix socket 的 connect(2)，bubblewrap 实验收发成功 |
| M5(撤回) | "actions/checkout@v7 不存在" | — | 误报：git ls-remote 与 GitHub Release 均确认 v7/v7.0.1 存在 |

## 验证方法

- 所有 shell 脚本通过 `bash -n`。
- 问题 1：构造 `../escaped` 与 `../../escape/management-scripts/run`，修复前可在 BaseDir 外创建目录并执行脚本；修复后入口直接拒绝（rc=2），无任何文件副作用。
- 问题 2：创建 `instances/work`、`instances/personal` 后执行 sync，正确生成两个 .desktop；修复前只生成错误的 `adspower-appimage-instances.desktop`。
- 问题 5：模拟函数中途失败的 EXIT trap 清理，残留为 0。
- 问题 6：两个 app，第一个退出码 9，第二个仍被执行，最终汇总失败并以非零退出。
- 问题 7：`env -u USER` 下启动器不再因 unbound variable 退出（127）。
- bubblewrap socket 只读绑定实验：沙箱内客户端 connect + 收发数据成功（ACK 往返）。

## 修复明细

### custom-appimage-manager
- 所有命令入口（app / run / shortcut / update-all）先执行 `valid_app` 校验，再做任何文件操作；update-all 对目录名同样校验。
- self-update：临时文件改建于目标同目录（同文件系统 rename 原子替换），trap 改为 EXIT 并在成功后显式清除。
- update-all：单 app 失败不再中断循环，结尾汇总失败项并以非零退出；README 同步说明该语义。

### adspower/management-scripts/
- shortcut：sync 的 find 路径修正为 `~/.local/share/adspower-appimage/instances`；create_shortcut 写入绝对路径 `Exec=$HOME/.local/bin/custom-appimage-manager run <instance>`。
- check："是否最新"仅比较 release tag，移除 install 文件存在性条件。
- run-sandboxed.sh：`${USER:-$(id -un)}` 回退；删除 ENGINE 死分支与 `--bwrap` 参数，bwrap 缺失时报错退出。
- 删除重复的根级 `adspower/run-sandboxed.sh`，唯一保留 `management-scripts/run-sandboxed.sh`（引用方 `management-scripts/run` 使用相对路径，不受影响）。

### build-appimage.sh 与 CI
- 构建前清理旧的 `adspower-*-x86_64.AppImage`。
- 产物查找改为精确匹配本次构建的输出文件名，删除父目录兜底分支。
- CI 中 find 改为断言固定产物文件名 `adspower-${VERSION}-x86_64.AppImage` 存在。

## 遗留事项（有意不处理）

- install 不校验 `.sha256`（用户决定）。注意同一 Release 内 digest 与二进制同源，校验属完整性加固而非独立信任根。
- 未暴露 `/etc/machine-id`、D-Bus socket 等：暂无真实 GUI 启动失败证据，待实际运行日志再评估。