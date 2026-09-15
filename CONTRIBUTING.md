# 开发

[返回 README](README.md)

在仓库根目录运行：

```sh
# Python 测试
/usr/bin/python3 -m unittest discover -s tests -v

# 构建、签名检查和原生窗口测试
bash scripts/check.sh
```

测试使用临时数据和虚构任务。原生测试需要已登录的 macOS 图形桌面，会短暂显示测试工人。

主要代码：`native/Workers.swift` 负责窗口，`scripts/collector.py` 负责状态和离场计时，`scripts/lifecycle.py` 处理生命周期事件。三张工位图片在 `assets/workers/`。

修改状态判断时补充对应测试；保留只读数据访问，避免记录任务正文。编译产物、会话数据和凭据不提交到 Git。

更新预览图：

```sh
"dist/Codex Workers.app/Contents/MacOS/CodexWorkers" --render-preview assets/preview.png
"dist/Codex Workers.app/Contents/MacOS/CodexWorkers" --render-animation assets/preview.gif
```

提交后打包源码：

```sh
mkdir -p dist
git archive --format=zip --prefix=codex-workers/ --output=dist/codex-workers-source.zip HEAD
```

构建只包含当前 CPU 架构，最低部署目标为 macOS 13，采用本地 ad-hoc 签名，未公证。目前尚未指定开源许可证。

[架构](docs/architecture.md) · [插件](docs/plugin.md) · [素材](assets/README.md)
