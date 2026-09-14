#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then
  echo "Codex Workers requires macOS and Xcode Command Line Tools." >&2
  exit 1
fi
xcrun --find swiftc >/dev/null
/usr/bin/python3 --version >/dev/null
WORKERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_APP="$WORKERS_ROOT/dist/Codex Workers.app"
mkdir -p "$WORKERS_APP/Contents/MacOS" "$WORKERS_APP/Contents/Resources" "$WORKERS_ROOT/.build/module-cache"
xcrun swiftc -O -module-cache-path "$WORKERS_ROOT/.build/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework Cocoa "$WORKERS_ROOT/native/Workers.swift" \
  -o "$WORKERS_APP/Contents/MacOS/CodexWorkers"
cp "$WORKERS_ROOT/scripts/collector.py" "$WORKERS_APP/Contents/Resources/collector.py"
cp "$WORKERS_ROOT/scripts/lifecycle.py" "$WORKERS_APP/Contents/Resources/lifecycle.py"
cp "$WORKERS_ROOT/scripts/login_startup.py" "$WORKERS_APP/Contents/Resources/login_startup.py"
mkdir -p "$WORKERS_APP/Contents/Resources/Workers"
for sprite in working cheering sleeping; do
  cp "$WORKERS_ROOT/assets/workers/$sprite.png" "$WORKERS_APP/Contents/Resources/Workers/$sprite.png"
done
cp "$WORKERS_ROOT/native/Info.plist" "$WORKERS_APP/Contents/Info.plist"
codesign --force --sign - "$WORKERS_APP"
echo "Built: $WORKERS_APP"
