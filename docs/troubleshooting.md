# 安装与常见问题

[返回 README](../README.md)

## 安装与登录启动

先按 README 构建并退出正在运行的小队，再执行：

```sh
mkdir -p "$HOME/Applications"
ditto "dist/Codex Workers.app" "$HOME/Applications/Codex Workers.app"
open "$HOME/Applications/Codex Workers.app"
```

之后可在菜单开启「登录时自动启动」。它要求上述安装位置，手动退出后不会强制重启。卸载前先关闭该选项。

## 任务运行了，没有工人

- 确认菜单栏有小队图标；安装插件不会自动启动桌面应用。
- 确认任务正在执行，而不是只打开历史内容。云端、远程和旧版 CLI 任务不支持。
- 在菜单选择「显示所有工人」「将小队移回屏幕角落」或「重新连接」。首次扫描大型记录可能稍慢。
- 若 Codex 更新后持续报错，可能需要适配新的内部格式。

本地诊断在 `~/.codex-workers/runtime.json`，先看刷新时间是否新鲜。`workerCount` 是工人数，`visibleWindowCount` 是共享窗口数（0 或 1），`loadedSpriteCount` 应为 3。报告问题时只提供错误标记和数量，无需上传实际会话文件。

## 为什么完成后还在

默认从最后活跃时起保留 5 分钟：先欢呼，完成约 90 秒后睡眠，到期离场。可以在菜单缩短等待时间。

## 修改代码后还是旧版本

`scripts/launch.sh` 优先打开 `~/Applications/` 中的应用。退出旧实例，重新构建并打开 `dist/Codex Workers.app`，验证后再安装。

## 构建或测试失败

确认 Xcode Command Line Tools 和 `/usr/bin/python3` 可用。原生窗口测试需要已登录的 macOS 图形桌面；受限沙箱或无图形桌面的环境可能无法运行。
