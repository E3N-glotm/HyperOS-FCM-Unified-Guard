#!/usr/bin/env python3
"""Build alpha31 as a minimal verified delta over the published alpha30."""
import hashlib
import pathlib
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
base, target = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha256(base.read_bytes()).hexdigest() == "d56844ea18fa8e2e3158b6badaa1b586ded082d071e62d40f077a8957d1f460c"
guard = "bin/fcm_guard.sh"
helper = "bin/fcm_dns_hosts_fallback.sh"
note = "ALPHA31_NATIVE_DNS_RECOVERY.txt"
patches = {p: (root / "module" / p).read_bytes().replace(b"\r\n", b"\n") for p in (guard, helper)}
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as dst:
    assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
    assert not ({helper, note} & set(src.namelist()))
    for info in src.infolist():
        data = src.read(info.filename)
        if info.filename == guard:
            data = patches[guard]
        elif info.filename == "module.prop":
            assert b"version=0.4.0-alpha.30\n" in data and b"versionCode=40030\n" in data
            data = data.replace(b"version=0.4.0-alpha.30\n", b"version=0.4.0-alpha.31\n").replace(b"versionCode=40030\n", b"versionCode=40031\n")
        elif info.filename == "customize.sh":
            data += b'\n# alpha31: bounded resolver recovery helper\nset_perm "$MODPATH/bin/fcm_dns_hosts_fallback.sh" 0 0 0755\n'
        dst.writestr(info, data)
    info = zipfile.ZipInfo(helper)
    info.create_system = 3
    info.external_attr = 0o100755 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    dst.writestr(info, patches[helper])
    dst.writestr(note, "alpha31: bounded TLS-verified native resolver recovery, cellular only, no VPN/private DNS override. Temporary exact-name overlay with cleanup; overnight validation pending.\n")
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None
    assert set(dst.namelist()) == set(src.namelist()) | {helper, note}
    assert len(dst.namelist()) == len(set(dst.namelist()))
    for name in src.namelist():
        if name not in {guard, "module.prop", "customize.sh"}:
            assert src.read(name) == dst.read(name), name
    for name, data in patches.items():
        assert dst.read(name) == data and (dst.getinfo(name).external_attr >> 16) & 0o111
    assert b"versionCode=40031\n" in dst.read("module.prop")
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix(".zip.sha256").write_text(f"{digest}  {target.name}\n", encoding="ascii")
print("ALPHA31 PACKAGE VERIFIED", digest)
