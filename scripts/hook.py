#!/usr/bin/env python3
"""Advisory, fail-open hooks. Store only identifiers + event type + timestamp."""
import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time

EVENTS = {'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest',
          'PostToolUse', 'Stop', 'Interrupt', 'SessionEnd'}


def record(event, root=None):
    sid = event.get('session_id', '')
    kind = event.get('hook_event_name')
    if not isinstance(sid, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', sid) or kind not in EVENTS:
        return
    root = root or Path(os.environ.get('CODEX_WORKERS_DATA', str(Path.home() / '.codex-workers')))
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    dest = root / (sid + '.json')
    at = time.time()
    payload = {'session_id': sid, 'event': kind, 'at': at,
               'turn_id': str(event.get('turn_id') or '')[:128]}
    # Per-session serialization prevents partial JSON and older invocations overwriting newer ones.
    with (root / (sid + '.lock')).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            old = json.loads(dest.read_text())
        except (ValueError, OSError):
            old = {}
        if old.get('at', 0) > at:
            return
        fd, name = tempfile.mkstemp(prefix=sid + '.', dir=root)
        try:
            with os.fdopen(fd, 'w') as out:
                json.dump(payload, out)
            os.replace(name, dest)
        finally:
            if os.path.exists(name):
                os.unlink(name)


if __name__ == '__main__':
    try:
        record(json.load(sys.stdin))
    except Exception:
        pass  # A visualization must never block the agent or decide an approval.
