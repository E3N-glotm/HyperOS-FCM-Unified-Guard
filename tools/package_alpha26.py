#!/usr/bin/env python3
"""Build exact reviewed alpha26 delta against published alpha25."""
import hashlib
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_SHA = '7c6a8715f8911456326ab368f721288a4005d4c7b130ae0887bce16c6e976b5f'
REPLACE = {
    'bin/pk_boot_guard.sh': 'static-patch/overlay/bin/pk_boot_guard.sh',
    'customize.sh': 'static-patch/overlay/customize.sh',
    'bin/fcm_guard.sh': 'module/bin/fcm_guard.sh',
}
NOTE = 'ALPHA26_BOOT_ALARM_DNS.txt'
base, target = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha256(base.read_bytes()).hexdigest() == BASE_SHA
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as dst:
    assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
    for info in src.infolist():
        name = info.filename
        data = src.read(name)
        if name in REPLACE:
            data = (ROOT / REPLACE[name]).read_bytes().replace(b'\r\n', b'\n')
            assert data.startswith(b'#!/system/bin/sh') and b'\r' not in data
        elif name == 'module.prop':
            assert b'version=0.4.0-alpha.25\n' in data and b'versionCode=40025\n' in data
            data = data.replace(b'version=0.4.0-alpha.25\n', b'version=0.4.0-alpha.26\n').replace(b'versionCode=40025\n', b'versionCode=40026\n')
        if name in REPLACE or name == 'bin/fcmu_alarm_wait':
            info.create_system = 3
            info.external_attr = (0o100755 << 16)
        dst.writestr(info, data)
    dst.writestr(NOTE, 'alpha26: early boot firmware evidence and gate trace; repair alarm helper executable permission; optional cellular recreation defaults off.\n')
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None and len(dst.namelist()) == len(set(dst.namelist()))
    assert set(dst.namelist()) == set(src.namelist()) | {NOTE}
    for name in src.namelist():
        if name not in REPLACE and name != 'module.prop':
            assert src.read(name) == dst.read(name), name
    assert (dst.getinfo('bin/fcmu_alarm_wait').external_attr >> 16) & 0o111
    assert b'versionCode=40026\n' in dst.read('module.prop')
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n', encoding='ascii')
print('ALPHA26 PACKAGE VERIFIED', digest)
