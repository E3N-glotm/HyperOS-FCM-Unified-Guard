#!/usr/bin/env python3
"""Build one real, installable Magisk ZIP: static FCM guard + scoped Zygisk.

This combines a *tested* adaptive static package and a diagnostics-OFF
production arm64 PowerKeeper library. It is an integration candidate, not
a claimed drop-in equivalent to legacy LSPosed / Millet Guard on every ROM.
"""
from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import zipfile

VERSION = "0.4.0-alpha.8"
VERSION_CODE = "40008"
MOD_ID = "fcm_unified_guard"
OUTPUT_NAME = f"HyperOS-FCM-Unified-Guard-v{VERSION}-integrated-candidate.zip"
DEFAULT_PACKAGES = b"com.miui.powerkeeper\ncom.xiaomi.powerkeeper\n"
BASELINE_REPORT = (
    b"pk.equivalence\tunverified\tNative runtime pending actual method validation\n"
)
VERSION_INFO = f"""id={MOD_ID}
name=HyperOS FCM Unified Guard (Magisk + Zygisk)
version={VERSION}
versionCode={VERSION_CODE}
author=E3N
description=FCM/Millet guard + scoped PowerKeeper runtime; OEM hooks independently degrade; delivery unverified
""".encode()

NOTICE = b"""# FCM Unified Guard integrated Magisk candidate

This is ONE Magisk module. No LSPosed bridge or APK is included.
The optional PowerKeeper Zygisk library supports arm64; it does not replace
Xiaomi's APK and does not inject into system_server or GMS processes.
If Zygisk or the matching OEM API is absent, the independent FCM core remains.
A prior unacknowledged boot quarantines ONLY the PowerKeeper runtime via
backend/powerkeeper-hook.disable. The user can disable the whole module in
Magisk. Do not confuse method installation with FCM delivery equivalence.

Build policy:
* Only the diagnostics-OFF native output can enter this ZIP.
* The real native library must never include the ART isolated test JNI.
* Existing framework adaptation is not asserted to cover every ROM.
* Do not publish as a stable release before OEM delivery and battery tests.
"""

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def validate_relpath(name: str) -> None:
    p = PurePosixPath(name)
    if not name or name.startswith("/") or "\\" in name or any(c in name for c in ("\0", "\r", "\n")):
        raise ValueError(f"Invalid zip path {name!r}")
    if ".." in p.parts or p.as_posix() != name:
        raise ValueError(f"Unsafe zip path {name!r}")

def load_inputs(static_zip: Path, so: Path, dex: Path) -> dict[str, bytes]:
    binary = so.read_bytes()
    bridge = dex.read_bytes()
    if binary[:5] != b"\x7fELF\x02" or int.from_bytes(binary[18:20], "little") != 183:
        raise ValueError("Not ELF64 arm64 PowerKeeper native library")
    if len(binary) < 50000 or b"zygisk_module_entry" not in binary:
        raise ValueError("Missing Zygisk native module symbol")
    if (b"/data/adb/fcmu_pk_experiment/zygisk-stage.tsv" in binary
        or b"Java_ArtInitSelfTest_installHook" in binary):
        raise ValueError("Refusing diagnostic or isolated-test native build")
    if not bridge.startswith(b"dex\n") or len(bridge) < 1000:
        raise ValueError("Bridge DEX invalid")

    files: dict[str, bytes] = {}
    with zipfile.ZipFile(static_zip) as z:
        if z.testzip() is not None:
            raise ValueError("Bad source static ZIP CRC")
        for item in z.infolist():
            if item.is_dir():
                continue
            validate_relpath(item.filename)
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Symlink in original ZIP")
            if item.filename in files:
                raise ValueError("Duplicate path in original ZIP")
            files[item.filename] = z.read(item.filename)
    for required in ("module.prop", "skip_mount", "post-fs-data.sh",
                     "service.sh", "customize.sh", "core-service.sh",
                     "bin/reconcile.sh", "bin/powerkeeper_probe.sh",
                     "bin/powerkeeper_processes.sh", "tools/patcher.jar"):
        if required not in files:
            raise ValueError(f"Missing static guard component: {required}")
    if not files["module.prop"].startswith(f"id={MOD_ID}\n".encode()):
        raise ValueError("Unexpected Magisk module ID")
    if "zygisk/arm64-v8a.so" in files or "powerkeeper-runtime.dex" in files:
        raise ValueError("Static artifact already contains runtime")
    if any(p.startswith(("bridge/", "system/", "patched/")) or p.endswith(".apk") for p in files):
        raise ValueError("Old LSPosed bridge or OEM system replacement in base ZIP")

    files["module.prop"] = VERSION_INFO
    files["zygisk/arm64-v8a.so"] = binary
    files["powerkeeper-runtime.dex"] = bridge
    files["backend/powerkeeper-packages.list"] = DEFAULT_PACKAGES
    files["backend/powerkeeper-capabilities.tsv"] = BASELINE_REPORT
    files["INTEGRATED_CANDIDATE.md"] = NOTICE
    return files

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-zip", type=Path, required=True)
    parser.add_argument("--static-sha256", required=True)
    parser.add_argument("--native-so", type=Path, required=True)
    parser.add_argument("--dex", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    source_hash = sha256(args.static_zip.read_bytes())
    if source_hash != args.static_sha256.lower():
        raise SystemExit("Static artifact digest mismatch")
    files = load_inputs(args.static_zip, args.native_so, args.dex)
    for name in files:
        validate_relpath(name)
    if args.check_only:
        print("INTEGRATED_INPUTS_AUDITED_OK", len(files))
        return

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 31, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            executable = name.endswith(".sh") or name in ("bin/milletctl", "bin/bridgectl")
            info.external_attr = (0o100755 if executable else 0o100644) << 16
            data = files[name]
            if name.endswith((".sh", ".prop", ".md", ".conf")):
                data = data.replace(b"\r\n", b"\n")
            z.writestr(info, data)
    with zipfile.ZipFile(args.out) as z:
        assert z.testzip() is None
        names = z.namelist()
        assert len(names) == len(set(names))
        assert "zygisk/arm64-v8a.so" in names
        assert "powerkeeper-runtime.dex" in names
        assert not any(n.endswith(".apk") or n.startswith("bridge/") for n in names)
        assert not any(b"\r" in z.read(n) for n in names if n.endswith(".sh"))
    digest = sha256(args.out.read_bytes())
    args.out.with_suffix(".zip.sha256").write_text(
        digest + "  " + args.out.name + "\n", encoding="ascii"
    )
    print("INTEGRATED_MAGISK_CANDIDATE_CREATED", args.out)
    print("PACKAGE_SHA256", digest)
    print("STATIC_SHA256", source_hash)
    print("NATIVE_SO_SHA256", sha256(files["zygisk/arm64-v8a.so"]))
    print("JAVA_DEX_SHA256", sha256(files["powerkeeper-runtime.dex"]))
    print("INSTALLABLE_MAGISK_LAYOUT_OK (not stable / end-to-end unverified)")

if __name__ == "__main__":
    main()
