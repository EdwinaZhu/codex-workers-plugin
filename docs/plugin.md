# 可选插件

[返回 README](../README.md)

应用可独立运行。Codex 插件提供启动、诊断入口，以及可选的工具调用和审批事件。

- `.codex-plugin/plugin.json`：插件清单。
- `skills/workers/SKILL.md`：启动与诊断操作。
- `hooks/hooks.json`：可选事件配置。

下载仓库不会自动安装插件。在支持插件管理的 Codex 中，可以请求「把此目录中的 codex-workers 安装为我的本地插件，保留已有 marketplace 条目」。安装后在新任务中说「显示我的 Codex 工人小队」。

如果已经把插件加入自己的 marketplace，可用其实际名称安装：

```sh
codex plugin add codex-workers --marketplace YOUR_MARKETPLACE
```

Hooks 需在 Codex 中单独审阅、信任。它们只保存事件元数据，不处理审批。审批标记会在后续事件到来时清除，最久约 3 分钟后回退为工作中。

改动源码不会自动更新已安装的插件缓存或桌面应用，需要分别重新安装。本地插件开发可用版本缓存后缀触发更新。
