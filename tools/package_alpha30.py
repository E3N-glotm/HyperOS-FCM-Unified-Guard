#!/usr/bin/env python3
"""Build alpha30 as a minimal, verified delta to the published alpha29."""
import hashlib
import pathlib
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
base, target, native = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha256(base.read_bytes()).hexdigest() == "7164241ef13866426a564a9c034867f611a04c61fbc36d27b4d89c188e018df6"
guard = "bin/fcm_guard.sh"
helper = "bin/fcm_socket_keepalive.sh"
binary = "bin/fcmu_socket_keepalive"
note = "ALPHA30_MCS_TCP_KEEPALIVE.txt"
patches = {p: (root / "module" / p).read_bytes().replace(b"\r\n", b"\n") for p in (guard, helper)}
patches[binary] = native.read_bytes()
assert patches[binary][:4] == b"\x7fELF" and patches[binary][18:20] == b"\xb7\x00"
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as dst:
    assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
    assert not ({helper, binary, note} & set(src.namelist()))
    for info in src.infolist():
        data = src.read(info.filename)
        if info.filename == guard:
            data = patches[guard]
        elif info.filename == "module.prop":
            assert b"version=0.4.0-alpha.29\n" in data and b"versionCode=40029\n" in data
            data = data.replace(b"version=0.4.0-alpha.29\n", b"version=0.4.0-alpha.30\n").replace(b"versionCode=40029\n", b"versionCode=40030\n")
        elif info.filename == "customize.sh":
            data += b'\n# alpha30: native socket helper executable\nif [ -f "$MODPATH/bin/fcmu_socket_keepalive" ]; then\n  set_perm "$MODPATH/bin/fcmu_socket_keepalive" 0 0 0755\nfi\n'
        dst.writestr(info, data)
    for name in (helper, binary):
        info = zipfile.ZipInfo(name)
        info.create_system = 3
        info.external_attr = 0o100755 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        dst.writestr(info, patches[name])
    dst.writestr(note, "alpha30: scoped MCS TCP keepalive, exact endpoint and socket identity verification, safe unsupported fallback. Long-duration push validation pending.\n")
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None
    assert set(dst.namelist()) == set(src.namelist()) | {helper, binary, note}
    assert len(dst.namelist()) == len(set(dst.namelist()))
    for name in src.namelist():
        if name not in {guard, "module.prop", "customize.sh"}:
            assert src.read(name) == dst.read(name), name
    for name, data in patches.items():
        assert dst.read(name) == data and (dst.getinfo(name).external_attr >> 16) & 0o111
    assert b"versionCode=40030\n" in dst.read("module.prop")
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix(".zip.sha256").write_text(f"{digest}  {target.name}\n", encoding="ascii")
print("ALPHA30 PACKAGE VERIFIED", digest)
