#!/usr/bin/env python3
"""Verified minimal delta over alpha31."""
import hashlib
import pathlib
import sys
import zipfile
root = pathlib.Path(__file__).resolve().parents[1]
base, target = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha256(base.read_bytes()).hexdigest() == "57820709ba2d0268695765ea48f0de71702b25022472ce5e6b29b21dda265af6"
helper = "bin/fcm_dns_hosts_fallback.sh"
data = (root / "module" / helper).read_bytes().replace(b"\r\n", b"\n")
note = "ALPHA32_DNS_RECOVERY_BUDGET.txt"
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as dst:
    assert src.testzip() is None and len(src.namelist()) == len(set(src.namelist()))
    assert helper in src.namelist() and note not in src.namelist()
    for info in src.infolist():
        content = src.read(info.filename)
        if info.filename == helper:
            content = data
        elif info.filename == "module.prop":
            assert b"version=0.4.0-alpha.31\n" in content and b"versionCode=40031\n" in content
            content = content.replace(b"version=0.4.0-alpha.31\n", b"version=0.4.0-alpha.32\n").replace(b"versionCode=40031\n", b"versionCode=40032\n")
        dst.writestr(info, content)
    dst.writestr(note, "alpha32: separate readiness probes from actual DNS recovery attempts; scoped wake lock and explicit stage diagnostics. Overnight real-world validation pending.\n")
with zipfile.ZipFile(base) as src, zipfile.ZipFile(target) as dst:
    assert dst.testzip() is None
    assert set(dst.namelist()) == set(src.namelist()) | {note}
    assert len(dst.namelist()) == len(set(dst.namelist()))
    assert dst.read(helper) == data and (dst.getinfo(helper).external_attr >> 16) & 0o111
    assert b"versionCode=40032\n" in dst.read("module.prop")
    for name in src.namelist():
        if name not in {helper, "module.prop"}:
            assert src.read(name) == dst.read(name), name
digest = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix(".zip.sha256").write_text(f"{digest}  {target.name}\n", encoding="ascii")
print("ALPHA32 PACKAGE VERIFIED", digest)
