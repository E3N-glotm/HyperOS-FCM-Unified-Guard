#!/usr/bin/env python3
"""Build a byte-preserving alpha33 update from the audited alpha32 release.

Do not reconstruct the Magisk archive from module/: that directory lacks the
production Zygisk, PowerKeeper DEX and alarmtimer assets.
"""
from __future__ import annotations

import hashlib
import pathlib
import sys
import zipfile

BASE_SHA256 = "88c306cf02b1d6d71c0c9738e0c6c94f832016229da4fe47120e3c13b0e9ba9e"
OLD_VERSION = b"version=0.4.0-alpha.32\n"
NEW_VERSION = b"version=0.4.0-alpha.33\n"
OLD_CODE = b"versionCode=40032\n"
NEW_CODE = b"versionCode=40033\n"
GUARD = "bin/fcm_guard.sh"
MANIFEST = "module.prop"
NOTE = "ALPHA33_AUTONOMOUS_FCM_RECOVERY.txt"
CHANGED = frozenset((GUARD, MANIFEST))


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def package(base_path: pathlib.Path, output_path: pathlib.Path, guard_path: pathlib.Path | None = None) -> None:
    repo = pathlib.Path(__file__).resolve().parents[1]
    base_bytes = base_path.read_bytes()
    assert sha(base_bytes) == BASE_SHA256, "alpha32 base is not the audited GitHub release"

    guard_bytes = (guard_path or (repo / "module/bin/fcm_guard.sh")).read_bytes()
    blob = hashlib.sha1(b"blob " + str(len(guard_bytes)).encode("ascii") + b"\0" + guard_bytes).hexdigest()
    assert blob == "f84b8132cba8bf8572c8c3a1efb7c25a695fb4c8", (
        "FCM recovery source changed without updating the audited alpha33 source revision"
    )
    assert guard_bytes.startswith(b"#!/system/bin/sh\n")
    assert b"\r" not in guard_bytes, "guard must use LF"
    required = (
        b"fcm_mcs_endpoint_socket_ready",
        b"5228|5229|5230|443",
        b"alt2-mtalk.google.com",
        b"fcm_default_net_validated",
        b"run_timeout dumpsys connectivity 2>/dev/null | awk",
        b"verified_mcs",
        b"[ \"$outage\" -ge 1800 ]",
        b"actual_uid",
        b"fcm_mcs_endpoint_socket_ready \"$endpoint\"",
    )
    for token in required:
        assert token in guard_bytes, f"required recovery guard missing: {token!r}"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(base_path) as src:
        names = src.namelist()
        assert src.testzip() is None
        assert len(names) == len(set(names)), "duplicate entries in base"
        assert GUARD in names and MANIFEST in names
        assert NOTE not in names
        meta = src.read(MANIFEST)
        assert meta.count(OLD_VERSION) == 1 and meta.count(OLD_CODE) == 1
        updated_meta = meta.replace(OLD_VERSION, NEW_VERSION).replace(OLD_CODE, NEW_CODE)
        assert updated_meta != meta and b"version=0.4.0-alpha.33\n" in updated_meta

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as dst:
            for info in src.infolist():
                payload = src.read(info.filename)
                if info.filename == GUARD:
                    payload = guard_bytes
                elif info.filename == MANIFEST:
                    payload = updated_meta
                dst.writestr(info, payload)
            # Pin the new note's DOS timestamp and Unix file mode so
            # repeated builds do not change the ZIP just because clock time
            # advanced between local validation and GitHub Actions.
            note_info = zipfile.ZipInfo(NOTE, date_time=(2026, 11, 28, 0, 0, 0))
            note_info.compress_type = zipfile.ZIP_DEFLATED
            note_info.create_system = 3
            note_info.external_attr = 0o100644 << 16
            dst.writestr(
                note_info,
                (
                    "HyperOS FCM Unified Guard v0.4.0-alpha.33\n"
                    "Preserves all existing alpha32 native PowerKeeper/Zygisk, "
                    "alarmtimer, configuration and installer assets.\n"
                    "Repairs GMS UID-bound alternate MCS TCP443 detection, "
                    "genuine Socket attestation,\n"
                    "bounded recovery when DNS failures persist, and streaming "
                    "Android17 VALIDATED network checks.\n"
                    "Recovery may include a narrowly capped GMS-only restart, "
                    "never whole-device/Box/network resets.\n"
                    "Does not guarantee uninterrupted push service; "
                    "real overnight testing remains necessary.\n"
                ).encode("utf-8"),
            )

    with zipfile.ZipFile(base_path) as src, zipfile.ZipFile(output_path) as out:
        assert out.testzip() is None
        assert out.namelist() == src.namelist() + [NOTE]
        assert len(set(out.namelist())) == len(out.namelist())
        assert out.read(GUARD) == guard_bytes
        assert out.read(MANIFEST) == updated_meta
        for path in src.namelist():
            if path not in CHANGED:
                assert out.read(path) == src.read(path), f"unexpected modification: {path}"
                assert out.getinfo(path).external_attr == src.getinfo(path).external_attr
        assert out.getinfo(GUARD).external_attr & (0o111 << 16)
        for must_keep in (
            "zygisk/arm64-v8a.so",
            "powerkeeper-runtime.dex",
            "bin/fcmu_alarm_wait",
            "bin/fcmu_socket_keepalive",
            "bin/fcm_dns_box_repair.sh",
            "bin/fcm_dns_hosts_fallback.sh",
        ):
            assert out.read(must_keep) == src.read(must_keep)
    digest = sha(output_path.read_bytes())
    output_path.with_suffix(".zip.sha256").write_text(
        f"{digest}  {output_path.name}\n", encoding="ascii"
    )
    print(f"ALPHA33_RELEASE_VERIFIED {digest} entries={len(out.namelist())}")
    print("ALPHA32_CONTENT_PRESERVED_EXCEPT bin/fcm_guard.sh, module.prop, and new note")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: package_alpha33.py AUDITED_ALPHA32_ZIP OUTPUT_ALPHA33_ZIP [AUDITED_GUARD_SOURCE]")
    package(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
            pathlib.Path(sys.argv[3]) if len(sys.argv) == 4 else None)
