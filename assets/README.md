# 工位素材

| 文件 | 用途 |
| --- | --- |
| `workers/working.png` | 低头工作 |
| `workers/cheering.png` | 举手欢呼 |
| `workers/sleeping.png` | 歪头睡眠 |
| `preview.png` | README / 插件预览，使用虚构任务 |

三张工位图为本项目制作的 AI 辅助生成素材，经过本地透明背景处理。应用直接打包并加载这些 PNG；运行时不会生成图片或访问图像服务。

生产素材均为 340 × 360 像素的 RGBA PNG，等比绘制在正方形工位中。保留原有颜色和透明度，不添加不透明方格背景。`preview.png` 由 `Workers.swift` 的 `--render-preview` 命令生成。

本机的 `concepts/` 为开发草图，已被 Git 忽略，不属于源码分发包。素材许可随项目最终选择的许可另行明确；当前没有单独授权声明。
