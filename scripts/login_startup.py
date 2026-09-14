#!/usr/bin/env python3
"""Manage this user's local, login-only launcher. Never keep the app forcibly alive."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

LABEL = 'local.codex.workers.login'


def definition(app):
    return {'Label': LABEL, 'ProgramArguments': ['/usr/bin/open', '-g', str(app)],
            'RunAtLoad': True, 'KeepAlive': False, 'LimitLoadToSessionType': 'Aqua'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['enable', 'disable', 'status'])
    args = parser.parse_args()
    path = Path.home() / 'Library/LaunchAgents' / (LABEL + '.plist')
    domain = 'gui/' + str(os.getuid())
    if args.action == 'status':
        print(json.dumps({'enabled': path.exists(), 'path': str(path)}))
        return
    if args.action == 'disable':
        subprocess.run(['/bin/launchctl', 'bootout', domain + '/' + LABEL],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        path.unlink(missing_ok=True)
        print('Login startup disabled; the current app is unaffected.')
        return
    app = Path.home() / 'Applications/Codex Workers.app'
    with (app / 'Contents/Info.plist').open('rb') as f:
        if plistlib.load(f).get('CFBundleIdentifier') != 'local.codex.workers':
            raise RuntimeError('Canonical local Codex Workers app is missing')
    path.parent.mkdir(parents=True, exist_ok=True)
    content = plistlib.dumps(definition(app))
    temp = path.with_suffix('.plist.tmp')
    temp.write_bytes(content)
    os.chmod(temp, 0o644)
    os.replace(temp, path)
    subprocess.run(['/bin/launchctl', 'bootout', domain + '/' + LABEL],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(path)], check=True)
    print('Login startup enabled; quitting the app remains effective until the next login.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
