#!/bin/bash
set -euo pipefail
WORKERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKERS_ROOT"

/usr/bin/python3 -m unittest discover -s tests -v
bash scripts/build.sh
codesign --verify --strict "dist/Codex Workers.app"

# Native tests use synthetic workers and never launch the real collector.
WORKERS_TEST_DATA="$(mktemp -d "${TMPDIR:-/tmp}/codex-workers-test.XXXXXX")"
trap 'rm -rf "$WORKERS_TEST_DATA"' EXIT
CODEX_WORKERS_DATA="$WORKERS_TEST_DATA" \
  "dist/Codex Workers.app/Contents/MacOS/CodexWorkers" --smoke-test
