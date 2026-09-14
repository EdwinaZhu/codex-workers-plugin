# Codex Workers

[简体中文](README.md)

Turn active Codex tasks into tiny pixel workers on your Mac. One task, one desk, all together in a compact group.

![Workers working, cheering and sleeping](assets/preview.png)

- **See progress at a glance:** workers look down while working, cheer on completion, and sleep when idle.
- **Automatic arrival and departure:** active tasks join; each worker leaves after five minutes of inactivity, adjustable in the menu.
- **Small and always nearby:** 48 × 48-point cells by default. Drag any worker to move the whole group.
- **Local processing:** no runtime network requests, model calls or uploads.

## Get started

Requires macOS 13+, the Codex desktop app, Xcode Command Line Tools and `/usr/bin/python3`. Run `xcode-select --install` if you need the build tools.

Download the repository, then run from its directory:

```sh
bash scripts/build.sh
open "dist/Codex Workers.app"
```

Start a local task in Codex. A worker usually appears within about two seconds. Quit any existing copy through its menu before opening a new build.

## Controls

Hover to see a task name, click for details, and drag to move the squad. Right-click a worker or use the menu bar to change size, adjust the inactivity timeout, or hide the group.

With no active tasks, only the menu bar icon remains. Workers stay while their tasks are running; each inactivity timer is independent.

## Notes

Swift / AppKit draws the workers; Python reads local task status. No third-party runtime dependencies are required. The app works on its own; the Codex plugin is optional.

Only local Codex desktop tasks are supported. Internal file formats may change with Codex updates. This is not an official OpenAI product. The app interface and detailed documentation are currently in Chinese.

[Installation & troubleshooting](docs/troubleshooting.md) · [Development](CONTRIBUTING.md) · [Privacy](docs/privacy.md)
