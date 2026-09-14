# 开发与发布

[返回 README](README.md)

## 本地工作流

所有命令从仓库根目录执行。需要 macOS、Swift 编译器和 `/usr/bin/python3`；测试只使用 Python 标准库。

```sh
# 适配器、TTL 和隐私边界测试
/usr/bin/python3 -m unittest discover -s tests -v

# 构建、签名检查和原生测试
bash scripts/check.sh
```

完整检查会创建临时数据目录，使用虚构任务测试窗口、透明素材、状态切换、整组拖动、尺寸、补位和 TTL 清理。需要已登录的 macOS 图形桌面，会短暂显示测试窗口。它不会启动真实会话读取器或更改登录启动设置。

只构建应用：

```sh
bash scripts/build.sh
```

产物为 `dist/Codex Workers.app`，模块缓存位于 `.build/`；两者均不进入 Git。编译目标为当前 CPU 架构，最低部署目标为 macOS 13；最低部署目标不代表已经在每个系统版本实机验证。

## 素材预览

三张生产素材位于 `assets/workers/`。改动渲染或素材后，使用应用自己的渲染器生成预览：

```sh
"dist/Codex Workers.app/Contents/MacOS/CodexWorkers" \
  --render-preview assets/preview.png
```

预览使用虚构任务。请检查 48 点尺寸下是否仍可区分姿态，透明边缘是否保留，避免在仓库中加入真实任务截图。素材来源见 [assets/README.md](assets/README.md)。

## 修改约定

- UI 改动保留同一面板、正方形工位和整组拖动，除非改动本身就是重新设计这些行为。
- 状态判断的改动用虚构 SQLite 和记录文件验证，尤其覆盖恢复任务、数据库滞后、断连和终态优先级。
- 只有确认活跃才能创建工人或续期；读取错误不能伪装成活跃。
- 对记录文件只提取所需的生命周期元数据，不解析或落盘任务正文。
- 新增本地文件时同步更新隐私说明。日志、凭据、数据库、编译缓存和开发草图不提交。
- 不在脚本、清单或文档中写入开发者的绝对路径，也不依赖本机 Codex 技能目录才能运行构建。

## 发布前

1. 更新 README 中的行为、限制和安装说明；中英文首页保持一致。
2. 核对 `.codex-plugin/plugin.json` 与 `native/Info.plist` 的基础版本，保留必要的插件结构。
3. 执行 `bash scripts/check.sh`，查看预览和 `git diff --check`。
4. 检查 `git ls-files` 中没有本机数据、构建产物或概念草图，并从干净的源码导出目录验证构建。
5. 若选择开源许可证，补充对应 `LICENSE` 并更新两个 README 的许可说明；目前尚未指定许可证。
6. 确定目标 GitHub 仓库及可见性后再推送。不要把个人 marketplace 文件、任务数据或 `.codex/` 目录加入仓库。

源码版本提交后，可以仅从 Git 中已提交的文件创建分发包：

```sh
mkdir -p dist
git archive --format=zip --prefix=codex-workers/ \
  --output=dist/codex-workers-source.zip HEAD
```

仓库归档包含源码和生产素材，不含 `.app`。如果之后提供二进制 Release，需要另行处理架构、签名、公证和其他 Mac 上的安装验证；当前构建脚本只做本地 ad-hoc 签名。
