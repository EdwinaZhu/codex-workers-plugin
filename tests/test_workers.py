import contextlib
from datetime import datetime, timezone
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from collector import Roster, classify, snapshot, ttl_setting
from hook import record
from lifecycle import LifecycleTail, parse_prefix, reconcile


def worker(sid='one', active=True, status='working'):
    return dict(id=sid, title='Example', project='Test', active=active, status=status,
                label='Test', detail='', loaded=active, color=1)


def scan(now, *workers, error=None):
    return dict(at=now, workers=list(workers), error=error, hookCount=0)


def lifecycle_record(kind, turn='new', at=100, ordinal=True, **extra):
    row = {'timestamp': datetime.fromtimestamp(at, timezone.utc).isoformat()}
    if ordinal:
        row['ordinal'] = 1
    row.update(type='event_msg', payload=dict(type=kind, turn_id=turn, **extra))
    return json.dumps(row).encode() + b'\n'


class LeaseTests(unittest.TestCase):
    def test_existing_idle_sessions_never_spawn(self):
        roster = Roster()
        self.assertEqual(roster.update(scan(100, worker(active=False)))['workers'], [])

    def test_activity_renews_and_idle_polling_does_not(self):
        r = Roster()
        r.update(scan(100, worker()), ttl=60)
        self.assertEqual(r.update(scan(145, worker()), ttl=60)['workers'][0]['expiresAt'], 205)
        for now in [146, 190, 204]:
            w = r.update(scan(now, worker(active=False, status='done')), ttl=60)['workers'][0]
            self.assertEqual(w['expiresAt'], 205)
        self.assertEqual(r.update(scan(205, worker(active=False)), ttl=60)['workers'], [])

    def test_working_longer_than_ttl_stays_and_restart_starts_empty(self):
        r = Roster()
        for t in range(0, 1200, 2):
            self.assertEqual(len(r.update(scan(t, worker()), ttl=10)['workers']), 1)
        self.assertEqual(Roster().update(scan(1200, worker(active=False)))['workers'], [])

    def test_each_worker_has_own_deadline_and_resume_keeps_identity(self):
        r = Roster()
        r.update(scan(10, worker('a'), worker('b')), ttl=20)
        rows = r.update(scan(29, worker('a', False), worker('b')), ttl=20)['workers']
        self.assertEqual({w['id']: w['expiresAt'] for w in rows}, {'a':30, 'b':49})
        rows = r.update(scan(30, worker('a', False), worker('b')), ttl=20)['workers']
        self.assertEqual([w['id'] for w in rows], ['b'])
        rows = r.update(scan(31, worker('a'), worker('b')), ttl=20)['workers']
        self.assertEqual(len({w['id'] for w in rows}), 2)

    def test_disappearance_and_read_errors_cannot_renew(self):
        r = Roster()
        r.update(scan(100, worker()), ttl=30)
        row = r.update(scan(110, error='db unavailable'), ttl=30)['workers'][0]
        self.assertFalse(row['active'])
        self.assertEqual(row['expiresAt'], 130)
        self.assertEqual(r.update(scan(130), ttl=30)['workers'], [])

    def test_ttl_setting_change_uses_last_activity(self):
        r = Roster()
        r.update(scan(100, worker()), ttl=300)
        self.assertEqual(r.update(scan(170, worker(active=False)), ttl=60)['workers'], [])

    def test_completed_turn_and_stale_hooks_cannot_claim_running(self):
        turn = dict(status='completed', completed_at=190, turn_id='new')
        self.assertEqual(classify(turn, True, dict(event='PermissionRequest', at=199, turn_id='new'), 200)[0], 'done')
        turn.update(status='inProgress', completed_at=None)
        self.assertEqual(classify(turn, True, dict(event='PermissionRequest', at=199, turn_id='old'), 200)[0], 'working')
        self.assertEqual(classify(turn, False, {}, 200)[0], 'unknown')


class AdapterTests(unittest.TestCase):
    def test_resumed_rollout_repairs_stale_interrupted_history_and_expires(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'thread-writer-locks').mkdir()
            (root / 'sessions').mkdir()
            path = root / 'sessions' / 'resumed.jsonl'
            path.write_bytes(lifecycle_record('task_started'))
            with sqlite3.connect(root / 'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads(id TEXT,name TEXT,cwd TEXT,updated_at INTEGER,source TEXT,thread_source TEXT,archived INTEGER,rollout_path TEXT)')
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)',
                           ('a','Resumed','/tmp/project',100,'vscode','user',0,str(path)))
            with sqlite3.connect(root / 'thread_history_1.sqlite') as db:
                db.execute('CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,started_at INTEGER,completed_at INTEGER,rollout_ordinal INTEGER)')
                db.execute('INSERT INTO thread_turns VALUES (?,?,?,?,?,?)',
                           ('a','old','interrupted',80,90,1))
            lifecycle = LifecycleTail()
            roster = Roster()
            def poll(now):
                return roster.update(snapshot(root, root/'events', now, lifecycle), ttl=10)
            with (root / 'thread-writer-locks/a.lock').open('w') as handle:
                fcntl.flock(handle, fcntl.LOCK_EX)
                active = poll(101)['workers'][0]
                self.assertEqual((active['active'], active['status'], active['statusSource']),
                                 (True, 'working', 'lifecycle'))
                with path.open('ab') as log:
                    log.write(lifecycle_record('task_complete', at=102))
                stopped = poll(102)['workers'][0]
                self.assertEqual((stopped['active'], stopped['status'], stopped['expiresAt']),
                                 (False, 'done', 111))
                self.assertEqual(poll(111)['workers'], [])
                # A new current file must supersede the old file and DB projection.
                rotated = root / 'sessions' / 'rotated.jsonl'
                rotated.write_bytes(lifecycle_record('task_started', turn='next', at=120))
                with sqlite3.connect(root / 'state_5.sqlite') as db:
                    db.execute('UPDATE threads SET rollout_path=?', (str(rotated),))
                self.assertTrue(poll(121)['workers'][0]['active'])
            # Persisted starts alone cannot renew activity once the holder leaves.
            self.assertFalse(poll(122)['workers'][0]['active'])
            self.assertEqual(poll(131)['workers'], [])

    def test_real_sqlite_and_lock_adapter_filters_helpers_and_is_read_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'thread-writer-locks').mkdir()
            dbpath = root / 'state_5.sqlite'
            with sqlite3.connect(dbpath) as db:
                db.execute('CREATE TABLE threads(id TEXT,name TEXT,title TEXT,cwd TEXT,updated_at INTEGER,source TEXT,thread_source TEXT,archived INTEGER)')
                db.executemany('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?)', [
                    ('a','Real session','Private prompt','/tmp/project',99,'vscode','user',0),
                    ('b','Idle','Private prompt','/tmp/project',99,'vscode','user',0),
                    ('c','Internal helper','Private prompt','/tmp/project',99,'subagent','guardian_review',0),
                    ('d','Archived','Private prompt','/tmp/project',99,'vscode','user',1)])
            with sqlite3.connect(root / 'thread_history_1.sqlite') as db:
                db.execute('CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,started_at INTEGER,completed_at INTEGER,rollout_ordinal INTEGER)')
                db.executemany('INSERT INTO thread_turns VALUES (?,?,?,?,?,?)', [
                    ('a','t1','inProgress',90,None,1), ('b','t2','completed',80,90,1),
                    ('c','t3','inProgress',90,None,1), ('d','t4','inProgress',90,None,1)])
            before = dbpath.read_bytes()
            with (root / 'thread-writer-locks/a.lock').open('w') as handle:
                fcntl.flock(handle, fcntl.LOCK_EX)
                result = Roster().update(snapshot(root=root,events=root/'events',now=100))
                self.assertIsNone(result['error'])
                self.assertEqual([w['id'] for w in result['workers']], ['a'])
                self.assertNotIn('Private prompt',json.dumps(result))
            self.assertEqual(dbpath.read_bytes(), before)
            self.assertEqual(Roster().update(snapshot(root=root,events=root/'events',now=101))['workers'], [])

    def test_unavailable_schema_is_visible_error(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertIsNotNone(snapshot(root=Path(folder))['error'])

    def test_hook_stores_only_allowlisted_metadata_and_rejects_path_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            record(dict(session_id='safe-id',hook_event_name='PermissionRequest',turn_id='turn',
                        prompt='secret',tool_input={'command':'secret'},transcript_path='/private'),root)
            value = json.loads((root/'safe-id.json').read_text())
            self.assertEqual(set(value), {'session_id','turn_id','event','at'})
            self.assertNotIn('secret',json.dumps(value))
            record(dict(session_id='../escape',hook_event_name='Stop'),root)
            self.assertFalse((root.parent/'escape.json').exists())
            self.assertEqual(ttl_setting(root),300)
            (root/'settings.json').write_text('{"ttlSeconds":60}')
            self.assertEqual(ttl_setting(root),60)


class LifecycleTests(unittest.TestCase):
    def test_incremental_records_partial_append_and_large_body_are_metadata_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'sessions').mkdir()
            path = root / 'sessions' / 'current.jsonl'
            path.write_bytes(lifecycle_record('task_started', ordinal=False))
            reader = LifecycleTail()
            started = reader.read(root, path)
            self.assertEqual(started['status'], 'inProgress')
            key = str(path.resolve())
            offset = reader.cache[key]['offset']
            self.assertEqual(reader.read(root, path), started)
            self.assertEqual(reader.cache[key]['offset'], offset)
            completion = lifecycle_record('task_complete', at=102,
                                          last_agent_message='PRIVATE-CONTENT' * 20000)
            with path.open('ab') as handle:
                handle.write(completion[:-1])
            self.assertIsNone(reader.read(root, path))
            self.assertEqual(reader.cache[key]['offset'], offset)
            with path.open('ab') as handle:
                handle.write(b'\n')
            result = reader.read(root, path)
            self.assertEqual((result['status'], result['started_at'], result['completed_at']),
                             ('completed', 100, 102))
            self.assertNotIn('PRIVATE-CONTENT', repr(reader.cache))
            self.assertEqual(reader.cache[key]['offset'], path.stat().st_size)

    def test_file_replacement_and_truncation_reset_previous_turn(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'sessions').mkdir()
            path = root / 'sessions' / 'current.jsonl'
            path.write_bytes(lifecycle_record('task_started', turn='old-long-id', padding='x'*100))
            reader = LifecycleTail()
            self.assertEqual(reader.read(root, path)['turn_id'], 'old-long-id')
            path.write_bytes(lifecycle_record('turn_aborted', turn='next', at=101))
            self.assertEqual(reader.read(root, path)['status'], 'interrupted')
            replacement = root / 'sessions' / 'replacement.jsonl'
            replacement.write_bytes(lifecycle_record('task_started', turn='latest', at=102))
            replacement.replace(path)
            self.assertEqual(reader.read(root, path)['turn_id'], 'latest')

    def test_embedded_events_invalid_headers_and_external_paths_are_ignored(self):
        fake = lifecycle_record('task_started').decode()
        message = json.dumps({'timestamp':'2026-09-10T00:00:00Z', 'type':'response_item',
                              'payload':{'content':fake}}).encode() + b'\n'
        self.assertIsNone(parse_prefix(message))
        self.assertIsNone(parse_prefix(lifecycle_record('unknown')))
        self.assertIsNone(parse_prefix(lifecycle_record('task_started').replace(
            b'1970-01-01T00:01:40+00:00', b'2026-99-99T00:00:00Z')))
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'sessions').mkdir()
            outside = root / 'outside.jsonl'
            outside.write_bytes(lifecycle_record('task_started'))
            symlink = root / 'sessions' / 'symlink.jsonl'
            symlink.symlink_to(outside)
            reader = LifecycleTail()
            self.assertIsNone(reader.read(root, outside))
            self.assertIsNone(reader.read(root, symlink))
            self.assertEqual(reader.cache, {})

    def test_incomplete_cold_scan_never_exposes_old_lifecycle(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'sessions').mkdir()
            path = root / 'sessions' / 'large.jsonl'
            with path.open('wb') as handle:
                handle.write(lifecycle_record('task_started'))
                for _ in range(17):
                    handle.write(b'{"type":"response_item","body":"' + b'x'*(1024*1024) + b'"}\n')
                handle.write(lifecycle_record('task_complete', at=102))
            reader = LifecycleTail()
            self.assertIsNone(reader.read(root, path))
            self.assertEqual(reader.read(root, path)['status'], 'completed')

    def test_reconciliation_preserves_newer_database_and_terminal_failure(self):
        started = parse_prefix(lifecycle_record('task_started'))
        db = dict(turn_id='old', status='interrupted', started_at=80, completed_at=90)
        self.assertEqual(reconcile(db, started), (started, 'lifecycle'))
        self.assertEqual(reconcile(None, started), (started, 'lifecycle'))
        self.assertEqual(reconcile(db, None), (db, 'database'))
        newer = dict(turn_id='latest', status='inProgress', started_at=110, completed_at=None)
        self.assertEqual(reconcile(newer, started), (newer, 'database'))
        failed = dict(turn_id='new', status='failed', started_at=100, completed_at=101)
        self.assertEqual(reconcile(failed, started), (failed, 'database'))
        complete = parse_prefix(lifecycle_record('task_complete', at=102))
        self.assertEqual(reconcile(failed, complete), (failed, 'database'))
        self.assertEqual(reconcile(dict(started), complete), (complete, 'lifecycle'))


if __name__ == '__main__':
    unittest.main()
