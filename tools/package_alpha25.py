#!/usr/bin/env python3
"""Overlay only reviewed alpha25 scripts on the immutable alpha24 release."""
import hashlib
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_SHA = 'ffe1e20ed98c13fa28a85bd406569314500ddf22d9fa2a2200fa08b38d5a9f9d'
REPLACEMENTS = {
    'post-fs-data.sh': 'static-patch/overlay/post-fs-data.sh',
    'service.sh': 'static-patch/overlay/service.sh',
    'customize.sh': 'static-patch/overlay/customize.sh',
    'bin/health_status.sh': 'module/bin/health_status.sh',
}
NEW = {'bin/pk_boot_guard.sh': 'static-patch/overlay/bin/pk_boot_guard.sh'}
NOTE = 'ALPHA25_POWERKEEPER_BOOT_RECOVERY.txt'
def sha(data): return hashlib.sha256(data).hexdigest()
def script(path):
    data = (ROOT / path).read_bytes().replace(b'\r\n', b'\n')
    assert b'\r' not in data and data.startswith(b'#!/system/bin/sh')
    return data
def main():
    base, target = map(pathlib.Path, sys.argv[1:])
    assert sha(base.read_bytes()) == BASE_SHA, 'alpha24 baseline digest mismatch'
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as dst:
        assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
        assert set(REPLACEMENTS) <= set(src.namelist())
        assert not (set(NEW) | {NOTE}) & set(src.namelist())
        for entry in src.infolist():
            data = src.read(entry.filename)
            if entry.filename in REPLACEMENTS:
                data = script(REPLACEMENTS[entry.filename])
            elif entry.filename == 'module.prop':
                assert b'version=0.4.0-alpha.24\n' in data and b'versionCode=40024\n' in data
                data = data.replace(b'version=0.4.0-alpha.24\n', b'version=0.4.0-alpha.25\n').replace(b'versionCode=40024\n', b'versionCode=40025\n')
            dst.writestr(entry, data)
        for name, data in [(name, script(path)) for name, path in NEW.items()] + [(NOTE, b'alpha25: boot-id-aware PowerKeeper quarantine, independent boot acknowledgement, one bounded normal-reboot recovery after a completed quarantined boot. No native or FCM transport changes.\n')]:
            info = zipfile.ZipInfo(name, (2026, 11, 18, 0, 0, 0))
            info.create_system = 3
            info.external_attr = ((0o100755 if name.endswith('.sh') else 0o100644) << 16)
            dst.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(base) as old, zipfile.ZipFile(target) as z:
        assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist()))
        assert set(z.namelist()) == set(old.namelist()) | set(NEW) | {NOTE}
        assert b'version=0.4.0-alpha.25\n' in z.read('module.prop')
        assert b'versionCode=40025\n' in z.read('module.prop')
        for path in old.namelist():
            if path not in REPLACEMENTS and path != 'module.prop':
                assert z.read(path) == old.read(path), f'unexpected change: {path}'
        for name, path in (REPLACEMENTS | NEW).items():
            assert z.read(name) == script(path)
            assert (z.getinfo(name).external_attr >> 16) & 0o111, name
        assert not any(n.endswith('.apk') or n.startswith('bridge/') for n in z.namelist())
    digest = sha(target.read_bytes())
    target.with_suffix('.zip.sha256').write_text(f'{digest}  {target.name}\n', encoding='ascii')
    print('ALPHA25 PACKAGE VERIFIED', digest, target)
if __name__ == '__main__': main()
