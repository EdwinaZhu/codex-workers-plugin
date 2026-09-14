# Codex Workers · 工人小队

[English](README.en.md)

把正在运行的 Codex 任务变成桌面上的像素小工人。一个任务一个工位，整齐挨在一起。

![工作、欢呼和睡眠中的小工人](assets/preview.png)

- **看姿态知进度**：工作时低头，完成时欢呼，空闲时睡觉。
- **自动出现和离场**：活跃任务加入小队；各自停止活动 5 分钟后离场，时间可调。
- **小巧常驻**：默认每格 48 × 48 点，拖动任意工人即可移动整组。
- **本机运行**：不联网、不调用模型、不上传数据。

## 开始使用

需要 macOS 13+、Codex 桌面应用、Xcode Command Line Tools 和 `/usr/bin/python3`。缺少编译工具时先运行 `xcode-select --install`。

下载仓库后，在仓库目录运行：

```sh
bash scripts/build.sh
open "dist/Codex Workers.app"
```

然后在 Codex 中开始一个本地任务，工人通常会在约 2 秒后出现。已有小队在运行时，先从菜单栏退出旧版本。

## 怎么操作

悬停查看任务名，点击查看详情，拖动移动整组。右键工人或点击菜单栏图标，可以调整大小、离场时间，或暂时收起小队。

没有活跃任务时只显示菜单栏图标。持续工作的工人会一直保留；每个人的离场时间独立计算。

## 说明

应用用 Swift / AppKit 显示工人，由 Python 读取本机任务状态，无第三方运行时依赖。可独立运行，Codex 插件是可选的。

目前只支持本机 Codex 桌面任务，依赖内部文件格式，Codex 更新后可能需要适配。本项目并非 OpenAI 官方产品。

[安装与常见问题](docs/troubleshooting.md) · [开发说明](CONTRIBUTING.md) · [隐私说明](docs/privacy.md)
