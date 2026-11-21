#!/usr/bin/env python3
"""Build and verify alpha29 against the published alpha28 install package."""
import hashlib
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_SHA = '0d878f8f6187bc312e32bd011e068785833a981bf31dea850eb7c555cd1e81f0'
GUARD_SHA = '49a00fa355b6777d32f9a33b5a4151cda5740bdf3d7a39d3329dcafc3967e496'
GUARD = 'bin/fcm_guard.sh'
NOTE = 'ALPHA29_LARGE_DUMP_RECOVERY.txt'
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
            assert b'version=0.4.0-alpha.28\n' in data and b'versionCode=40028\n' in data
            data = data.replace(b'version=0.4.0-alpha.28\n', b'version=0.4.0-alpha.29\n').replace(b'versionCode=40028\n', b'versionCode=40029\n')
        dst.writestr(info, data)
    dst.writestr(NOTE, 'alpha29: Large Android dumpsys output no longer passed as one exec argument. Verify default cellular network, VPN exclusion, subscription, and actual teardown using stdin. Overnight recovery and delayed delivery still require live verification.\n')
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None and len(dst.namelist()) == len(set(dst.namelist()))
    assert set(dst.namelist()) == set(src.namelist()) | {NOTE}
    for name in src.namelist():
        if name not in {GUARD, 'module.prop'}:
            assert src.read(name) == dst.read(name), name
    assert dst.read(GUARD) == guard
    assert (dst.getinfo(GUARD).external_attr >> 16) & 0o111
    assert (dst.getinfo('bin/fcmu_alarm_wait').external_attr >> 16) & 0o111
    assert b'versionCode=40029\n' in dst.read('module.prop')
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n', encoding='ascii')
print('ALPHA29 PACKAGE VERIFIED', digest)
