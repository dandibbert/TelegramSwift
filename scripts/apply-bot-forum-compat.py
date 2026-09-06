#!/usr/bin/env python3
"""Apply the reviewed, version-bound bot-forum backport to the pinned core.

No submodule ref or negotiated API layer is changed. Reject unknown source
revisions; don't substitute latest or silently ignore a failed patch.
"""
import pathlib
import subprocess
import sys
root = pathlib.Path(__file__).resolve().parent.parent
core = root / 'submodules/telegram-ios'
patch = root / 'scripts/patches/bot-forums.patch'
expected = 'a24bbe45f9861f736a79916a50898512f751e0dc'
actual = subprocess.check_output(['git', '-C', str(core), 'rev-parse', 'HEAD'], text=True).strip()
if actual != expected:
    sys.exit(f'Bot forum compatibility patch requires {expected}, got {actual}')
def check(*args):
    return subprocess.run(['git', '-C', str(core), 'apply', '--check', *args, str(patch)], capture_output=True, text=True)
forward = check()
if forward.returncode == 0:
    subprocess.run(['git', '-C', str(core), 'apply', str(patch)], check=True)
    print('Applied pinned bot forum compatibility backport.')
elif check('--reverse').returncode == 0:
    print('Pinned bot forum compatibility backport is already applied.')
else:
    sys.exit('Core source does not match the reviewed patch:\n' + forward.stderr)
serialization = (core / 'submodules/TelegramCore/Sources/State/Serialization.swift').read_text()
if 'return 210' not in serialization:
    sys.exit('Unexpected negotiated protocol layer; this backport is not a full schema upgrade.')
