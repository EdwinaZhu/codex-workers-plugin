#!/bin/bash
set -euo pipefail
WORKERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_INSTALLED="$HOME/Applications/Codex Workers.app"
if [ -x "$WORKERS_INSTALLED/Contents/MacOS/CodexWorkers" ]; then
  open "$WORKERS_INSTALLED"
  exit 0
fi
if [ ! -x "$WORKERS_ROOT/dist/Codex Workers.app/Contents/MacOS/CodexWorkers" ]; then
  bash "$WORKERS_ROOT/scripts/build.sh"
fi
open "$WORKERS_ROOT/dist/Codex Workers.app"
