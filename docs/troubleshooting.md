# 常见问题

[返回 README](../README.md)

## Codex 中有任务在运行，但没有工人

1. 确认菜单栏有小队的双人图标。单独下载或安装插件不会启动桌面常驻进程。
2. 确认任务此刻正在执行。只是打开着一个任务、正在输入、或查看历史内容，不会生成工人。
3. 菜单若显示「显示所有工人」，点击它；也可以选择「将小队移回屏幕角落」。
4. 查看菜单中的错误提示，尝试「重新连接」。首次读取大型历史记录可能需要多个轮询周期。
5. 确认是当前 Mac 的 Codex 桌面任务。云端、远程主机、旧版 CLI 记录及内部子任务不在支持范围内。

本地计数诊断位于 `~/.codex-workers/runtime.json`。`updatedAt` 是 Unix 时间戳；过期文件只描述上次运行，不表示当前状态。

| 字段 | 如何理解 |
| --- | --- |
| `workerCount` | 当前保留的工人数 |
| `activeCount` | 其中被确认活跃的数量 |
| `visibleWorkerCount` | 当前可见的方格数量 |
| `visibleWindowCount` | 共享窗口数量，只能是 0 或 1；不是工人数 |
| `loadedSpriteCount` | 应为 3 |
| `error` | 读取器或资源加载错误 |

如果 Codex 更新后持续失败，可能是内部数据结构变化。请报告系统版本、Codex 版本和错误标记，无需上传 SQLite、原始任务记录或真实任务截图。

## 修改了源码，打开后还是旧版本

`scripts/launch.sh` 优先使用 `~/Applications/Codex Workers.app`。从菜单退出旧实例后，重新构建并显式打开 `dist/Codex Workers.app`。验证完成后再复制到用户应用目录。

## 任务完成了，为什么工人还在

TTL 是有意保留的观察时间。从最后一次确认活跃开始倒计时，默认 5 分钟。刚完成时欢呼，完成约 90 秒后睡眠，到 TTL 截止才离场。可在菜单中缩短 TTL。

## 审批状态没有出现，或短暂滞后

审批标记需要安装插件并在 Codex 中审阅、信任 Hooks。普通状态显示无需 Hooks。

标记只表示最近检测到审批请求：后续事件会清除它，最久约 3 分钟后回退为工作中。它不是审批面板的精确实时镜像，也不会替用户处理审批。

## 登录后没有自动启动

将应用安装到 `~/Applications/Codex Workers.app`，再开启菜单中的「登录时自动启动」。可从仓库根目录检查配置：

```sh
/usr/bin/python3 scripts/login_startup.py status
```

该设置只控制下次图形登录。手动退出后不会自动重启。卸载前请先在菜单关闭登录自启；也可执行 `python3 scripts/login_startup.py disable`，再退出并移除应用。

## 无法构建或运行原生测试

```sh
xcode-select -p
xcrun --find swiftc
/usr/bin/python3 --version
```

缺少编译工具时先安装 Xcode Command Line Tools。`scripts/check.sh` 中的原生测试需要可访问 WindowServer 的已登录图形桌面；受限沙箱、无图形桌面的 SSH 环境或某些 CI 环境可能只能运行 Python 测试和构建。

本地构建是当前 CPU 架构的 ad-hoc 签名应用。项目尚未提供经过公证的分发安装包，不能把源码构建验证当作其他 Mac 上的安装验证。
