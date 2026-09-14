#!/usr/bin/env python3
"""Read-only Codex desktop adapter. Only status metadata is parsed or retained."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import time
from contextlib import closing
from lifecycle import LifecycleTail, reconcile


def data_root():
    return Path(os.environ.get('CODEX_WORKERS_DATA', str(Path.home() / '.codex-workers')))


def latest_db(root, stem):
    candidates = [p for p in root.glob(stem + '_*.sqlite') if p.stem.rsplit('_', 1)[1].isdigit()]
    if not candidates:
        raise FileNotFoundError(stem)
    return max(candidates, key=lambda p: int(p.stem.rsplit('_', 1)[1]))


def connect(path):
    db = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=.3)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA query_only=ON')
    return db


def loaded_ids(root):
    """Check existing writer locks without creating files or blocking writers."""
    loaded = set()
    for path in (root / 'thread-writer-locks').glob('*.lock'):
        if path.name.startswith('.'):
            continue
        try:
            with path.open('rb') as handle:
                try:
                    fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError:
                    loaded.add(path.stem)
                else:
                    fcntl.flock(handle, fcntl.LOCK_UN)
        except OSError:
            continue
    return loaded


def hook_record(root, thread_id):
    try:
        record = json.loads((root / (thread_id + '.json')).read_text())
        return record if isinstance(record, dict) else {}
    except (OSError, ValueError):
        return {}


def classify(turn, loaded, hook, now):
    """Persisted turn completion outranks delayed hooks; stale activity is unknown."""
    if not turn:
        return 'unknown', '等待状态', '缺少可读取的轮次记录'
    status = turn['status']
    if status == 'completed':
        finished = turn['completed_at'] or 0
        return ('done', '刚刚完成', '当前轮次已完成') if now - finished < 90 else ('idle', '休息中', '上一轮已完成')
    if status == 'failed':
        return 'error', '遇到问题', '上一轮失败，点击回到会话查看'
    if status == 'interrupted':
        return 'idle', '已暂停', '上一轮已中断'
    if status != 'inProgress':
        return 'unknown', '状态未知', '未识别的轮次状态'
    if not loaded:
        return 'unknown', '连接已离开', '记录仍在运行，但未检测到会话持有者'
    fresh = 0 <= now - hook.get('at', 0) < 180
    same_turn = hook.get('turn_id') and hook['turn_id'] == turn['turn_id']
    if fresh and same_turn:
        if hook.get('event') == 'PermissionRequest':
            return 'waiting', '有审批请求', '检测到审批请求；处理后的下一次事件会更新状态'
        if hook.get('event') == 'PreToolUse':
            return 'working', '正在动手', '正在调用工具'
    return 'working', '工作中', '当前轮次正在运行'


def snapshot(root=None, events=None, now=None, lifecycle=None):
    root = root or Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    events = events or data_root()
    now = time.time() if now is None else now
    lifecycle = lifecycle or LifecycleTail()
    result = {'workers': [], 'at': now, 'error': None, 'hookCount': 0}
    try:
        loaded = loaded_ids(root)
        with closing(connect(latest_db(root, 'state'))) as state, closing(connect(latest_db(root, 'thread_history'))) as history:
            columns = {r[1] for r in state.execute('PRAGMA table_info(threads)')}
            # `title` in some desktop versions contains the entire first prompt.
            # Only use the UI's explicit `name`; never export the prompt as a title.
            name = "COALESCE(NULLIF(name,''),'未命名会话')" if 'name' in columns else "'未命名会话'"
            rollout = 'rollout_path' if 'rollout_path' in columns else 'NULL AS rollout_path'
            source_filter = "AND (thread_source IS NULL OR thread_source='user')" if 'thread_source' in columns else ''
            ids = sorted(loaded)
            placeholders = ','.join('?' for _ in ids) or 'NULL'
            sql = f'''SELECT id,{name} AS label,cwd,updated_at,source,{rollout} FROM threads
                      WHERE archived=0 {source_filter} AND source NOT LIKE '%subagent%'
                      AND (updated_at>? OR id IN ({placeholders})) ORDER BY updated_at DESC'''
            rows = state.execute(sql, [now - 1800] + ids).fetchall()
            for row in rows:
                turn = history.execute('''SELECT turn_id,status,started_at,completed_at FROM thread_turns
                    WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1''', (row['id'],)).fetchone()
                turn = dict(turn) if turn else None
                marker = lifecycle.read(root, Path(row['rollout_path'])) if row['rollout_path'] else None
                turn, status_source = reconcile(turn, marker)
                hook = hook_record(events, row['id'])
                status, label, detail = classify(turn, row['id'] in loaded, hook, now)
                result['hookCount'] += int(bool(hook))
                result['workers'].append({
                    'id': row['id'], 'title': row['label'] or '未命名会话',
                    'project': Path(row['cwd']).name or row['cwd'],
                    'status': status, 'label': label, 'detail': detail,
                    'loaded': row['id'] in loaded,
                    'active': bool(turn and turn['status'] == 'inProgress' and row['id'] in loaded),
                    'statusSource': status_source,
                    'color': int(hashlib.sha256(row['id'].encode()).hexdigest()[:8], 16) % 6,
                })
    except (sqlite3.Error, OSError, ValueError) as exc:
        result['workers'] = []
        result['error'] = '无法读取 Codex 本机会话。请确认 Codex 已打开；当前适配器需要本机 state / thread_history 数据库。'
        result['diagnostic'] = type(exc).__name__
    return result


def ttl_setting(root=None):
    try:
        value = json.loads(((root or data_root()) / 'settings.json').read_text()).get('ttlSeconds', 300)
        return max(10, min(86400, int(value)))
    except (OSError, ValueError, TypeError, AttributeError):
        return 300


class Roster:
    """Only observed active sessions enter. TTL measures time since last active sighting.

    No roster is persisted: launching the app never resurrects old idle sessions.
    Polling idle records, hook files, or failures cannot renew a worker's lease.
    """
    def __init__(self):
        self.members = {}

    def update(self, scan, ttl=300, now=None):
        now = scan['at'] if now is None else now
        current = {w['id']: w for w in scan['workers']} if not scan.get('error') else {}
        for sid, worker in current.items():
            if worker['active']:
                if sid not in self.members:
                    self.members[sid] = {'worker': worker.copy(), 'lastActive': now, 'joinedAt': now}
                self.members[sid].update(worker=worker.copy(), lastActive=now)
            elif sid in self.members:
                self.members[sid]['worker'] = worker.copy()
        workers = []
        for sid, member in list(self.members.items()):
            expires = member['lastActive'] + ttl
            if now >= expires:
                del self.members[sid]
                continue
            worker = member['worker'].copy()
            if sid not in current:
                worker.update(active=False, status='unknown', label='连接已离开', detail='等待重新检测到活动；TTL 到期后撤掉')
            worker.update(expiresAt=expires, remaining=max(0, int(expires - now)), joinedAt=member['joinedAt'])
            workers.append(worker)
        workers.sort(key=lambda w: (w['joinedAt'], w['id']))
        return dict(scan, workers=workers, ttlSeconds=ttl)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--ttl', type=int, help='Override inactivity TTL in seconds (10–86400).')
    args = parser.parse_args()
    roster = Roster()
    lifecycle = LifecycleTail()
    try:
        while True:
            ttl = max(10, min(86400, args.ttl)) if args.ttl is not None else ttl_setting()
            print(json.dumps(roster.update(snapshot(lifecycle=lifecycle), ttl), ensure_ascii=False), flush=True)
            if not args.watch:
                break
            time.sleep(2)
    except (BrokenPipeError, KeyboardInterrupt):
        pass


if __name__ == '__main__':
    main()
