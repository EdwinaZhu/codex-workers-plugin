"""Incremental lifecycle metadata from the current rollout, without decoding message bodies."""
from datetime import datetime
import os
import re


# Only a top-level lifecycle record prefix is accepted. Strings inside messages,
# tool outputs, reasoning, and task_complete.last_agent_message are never parsed.
HEAD = re.compile(
    rb'^\s*\{\s*"timestamp"\s*:\s*"([0-9T:.+Z-]+)"\s*,\s*'
    rb'(?:"ordinal"\s*:\s*\d+\s*,\s*)?'
    rb'"type"\s*:\s*"event_msg"\s*,\s*"payload"\s*:\s*\{\s*'
    rb'"type"\s*:\s*"(task_started|task_complete|turn_aborted)"'
    rb'\s*,\s*"turn_id"\s*:\s*"([A-Za-z0-9_-]{1,128})"'
)


def parse_prefix(prefix):
    match = HEAD.match(prefix)
    if not match:
        return None
    stamp, kind, turn_id = (part.decode('ascii') for part in match.groups())
    try:
        at = datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None
    status = {'task_started': 'inProgress', 'task_complete': 'completed',
              'turn_aborted': 'interrupted'}[kind]
    return dict(turn_id=turn_id, status=status, event_at=at,
                started_at=at if status == 'inProgress' else None,
                completed_at=at if status != 'inProgress' else None)


class LifecycleTail:
    """Keep only offsets, file identity, and the latest lifecycle metadata in RAM."""
    def __init__(self):
        self.cache = {}

    def read(self, root, path):
        try:
            path = path.resolve()
            if not any(base.resolve() in path.parents for base in (root / 'sessions', root / 'archived_sessions')):
                return None
            with path.open('rb') as handle:
                stat = os.fstat(handle.fileno())
                identity = (stat.st_dev, stat.st_ino)
                key = str(path)
                state = self.cache.get(key)
                if not state or state['identity'] != identity or stat.st_size < state['offset']:
                    state = dict(identity=identity, offset=0, turn=None)
                    self.cache[key] = state
                handle.seek(state['offset'])
                # Bound cold-start work. A large history catches up over polls;
                # incomplete scans cannot supply a stale lifecycle as current.
                budget_end = state['offset'] + 16 * 1024 * 1024
                while handle.tell() < stat.st_size:
                    if handle.tell() >= budget_end:
                        return None
                    start = handle.tell()
                    prefix = handle.readline(1024)
                    chunk = prefix
                    # Skip the rest of the record in bounded chunks. Never JSON
                    # decode a transcript, response body, tool arguments, or output.
                    while chunk and not chunk.endswith(b'\n'):
                        chunk = handle.readline(64 * 1024)
                    if not chunk:
                        state['offset'] = start
                        return None
                    event = parse_prefix(prefix)
                    if event:
                        previous = state['turn']
                        if previous and previous['turn_id'] == event['turn_id']:
                            event['started_at'] = previous['started_at']
                        state['turn'] = event
                    state['offset'] = handle.tell()
                if len(self.cache) > 256:
                    for old in list(self.cache)[:-128]:
                        self.cache.pop(old, None)
                return state['turn'].copy() if state['turn'] else None
        except (OSError, ValueError):
            return None


def reconcile(database_turn, event_turn):
    """Current-file events repair lagging projections; DB failure detail still wins."""
    if not event_turn:
        return database_turn, 'database'
    if not database_turn:
        return event_turn, 'lifecycle'
    same_turn = database_turn['turn_id'] == event_turn['turn_id']
    if same_turn and database_turn['status'] in ('completed', 'interrupted', 'failed'):
        return database_turn, 'database'
    database_at = database_turn.get('completed_at') or database_turn.get('started_at') or 0
    if event_turn['event_at'] >= database_at:
        return event_turn, 'lifecycle'
    return database_turn, 'database'
