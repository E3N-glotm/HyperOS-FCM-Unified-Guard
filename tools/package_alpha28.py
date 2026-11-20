#!/usr/bin/env python3
"""Build and verify the phone-tested alpha28 guard delta against alpha27."""
import hashlib
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_SHA = '07f2a6749620df147e47516ac198e075a1b99f97b395274b365195c9cc573bfc'
GUARD_SHA = '94ffaa96610dbd7df657992f3b9fc1b9e320ae62dc7e3227b80b173256ccfacc'
GUARD = 'bin/fcm_guard.sh'
NOTE = 'ALPHA28_CELLULAR_RECOVERY.txt'
base, target = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha256(base.read_bytes()).hexdigest() == BASE_SHA
guard = (ROOT / 'module/bin/fcm_guard.sh').read_bytes().replace(b'\r\n', b'\n')
assert hashlib.sha256(guard).hexdigest() == GUARD_SHA
assert guard.startswith(b'#!/system/bin/sh') and b'\r' not in guard
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as dst:
    assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
    assert GUARD in src.namelist() and NOTE not in src.namelist()
    for info in src.infolist():
        name = info.filename
        data = src.read(name)
        if name == GUARD:
            data = guard
            info.create_system = 3
            info.external_attr = 0o100755 << 16
        elif name == 'module.prop':
            assert b'version=0.4.0-alpha.27\n' in data and b'versionCode=40027\n' in data
            data = data.replace(b'version=0.4.0-alpha.27\n', b'version=0.4.0-alpha.28\n').replace(b'versionCode=40027\n', b'versionCode=40028\n')
        dst.writestr(info, data)
    dst.writestr(NOTE, 'alpha28: opt-in cellular DNS recovery checks per-slot data settings, matching data subscription, actual network removal, restoration, and scoped wakelock. True overnight recovery remains unverified.\n')
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None and len(dst.namelist()) == len(set(dst.namelist()))
    assert set(dst.namelist()) == set(src.namelist()) | {NOTE}
    for name in src.namelist():
        if name not in {GUARD, 'module.prop'}:
            assert src.read(name) == dst.read(name), name
    assert dst.read(GUARD) == guard
    assert (dst.getinfo(GUARD).external_attr >> 16) & 0o111
    assert (dst.getinfo('bin/fcmu_alarm_wait').external_attr >> 16) & 0o111
    assert b'versionCode=40028\n' in dst.read('module.prop')
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n', encoding='ascii')
print('ALPHA28 PACKAGE VERIFIED', digest)
