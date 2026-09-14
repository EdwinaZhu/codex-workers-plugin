# 可选的 Codex 插件

[返回 README](../README.md)

桌面应用负责常驻显示；插件提供让 Codex 启动、诊断它的入口，以及可选事件信号。**基本会话检测不依赖插件。**

本仓库本身就是插件根目录：

| 路径 | 作用 |
| --- | --- |
| `.codex-plugin/plugin.json` | 名称、版本、界面介绍、技能和预览图 |
| `skills/workers/SKILL.md` | 启动与只读诊断流程 |
| `hooks/hooks.json` | 可选生命周期和工具事件 |
| `scripts/launch.sh` | 优先打开已安装的应用，否则使用本仓库构建 |

## 安装入口

插件需要通过 Codex 的 marketplace 机制安装。本仓库提供插件源码，不包含绑定某个用户目录的个人 marketplace 配置，也没有预设远程 marketplace 地址。下载 GitHub 仓库本身不会完成插件安装。

在支持插件管理的 Codex 中，可以请求「把此目录中的 codex-workers 安装为我的本地插件，保留已有 marketplace 条目」，由本地插件安装流程注册这个根目录。若正在维护自己的 marketplace，则先把本插件加入其配置，再使用该市场的实际名称：

```sh
codex plugin add codex-workers --marketplace YOUR_MARKETPLACE
```

上面的 `YOUR_MARKETPLACE` 需要替换为已配置的名称，不是项目内置的市场。安装后在新任务中尝试「显示我的 Codex 工人小队」或「检查工人小队的会话状态」。插件功能与管理入口随 Codex 版本而异；只想使用桌面工人时，按 README 构建并打开应用即可。

## Hooks

安装插件不等于信任 Hooks。需要在 Codex 自带的 Hooks 管理界面审阅并信任后，才会执行可选记录器。

事件包括 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`Stop`、`Interrupt` 和 `SessionEnd`。记录器只保存允许的事件元数据，无标准输出，不返回审批决定；写入失败不会阻塞任务。

读取器只采用与当前轮次匹配且足够新鲜的工具／审批信号；数据库终态优先于延迟事件。无需定时唤醒模型，也无需为每个工人创建 Codex 自动化。

## 开发版本

应用和仓库的基础版本为 `0.1.0`。本地插件迭代可能使用 `0.1.0+codex.<cachebuster>` 触发重新安装；缓存后缀不代表新的应用功能版本。

仓库中的变更不会自动更新已安装的插件缓存或 `~/Applications/` 中的应用。分别通过 Codex 的插件更新流程和 README 的应用安装步骤更新。
