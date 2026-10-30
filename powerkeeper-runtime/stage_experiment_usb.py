#!/usr/bin/env python3
"""Safely stage an experimental FCMU ZIP via USB ADB, without installing it.

This never reboots, switches Zygisk, clears user data, or touches Magisk
modules. It works without Wi-Fi when USB debugging is authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

REMOTE_DIR = "/data/local/tmp/fcmu-pr15-usb"
REMOTE_ZIP = f"{REMOTE_DIR}/scoped-experiment-disabled.zip"


def adb_binary(argument: str | None) -> str:
    if argument:
        target = Path(argument)
    else:
        lookup = shutil.which("adb")
        if lookup:
            return lookup
        suffix = ".exe" if os.name == "nt" else ""
        target = Path.home() / "AppData/Local/Android/Sdk/platform-tools" / ("adb" + suffix)
    if not target.is_file():
        raise RuntimeError("ADB unavailable; install Android platform-tools or use --adb PATH")
    return str(target)


def run(args: list[str], *, timeout: int = 35) -> str:
    proc = subprocess.run(args, text=True, capture_output=True, timeout=timeout,
                          encoding="utf-8", errors="replace", check=False)
    if proc.returncode:
        raise RuntimeError(f"command failed (rc={proc.returncode}): {proc.stderr.strip()}")
    return proc.stdout


def audit_archive(archive: Path, expected: str) -> tuple[str, int]:
    if not archive.is_file():
        raise RuntimeError(f"ZIP not found: {archive}")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
        raise RuntimeError("Expected SHA-256 must be 64 hexadecimal characters")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != expected.lower():
        raise RuntimeError(f"Refusing untrusted artifact: SHA mismatch {digest}")
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError("Corrupt ZIP member")
        names = set(z.namelist())
        required = {"disable", "skip_mount", "module.prop", "zygisk/arm64-v8a.so",
                    "powerkeeper-runtime.dex", "post-fs-data.sh", "service.sh"}
        if not required <= names or z.read("disable") != b"":
            raise RuntimeError("Not an explicitly disabled experimental module")
        if b"id=fcmu_pk_experiment" not in z.read("module.prop"):
            raise RuntimeError("Unexpected module ID")
        if any(name.startswith("system/") or "lsposed" in name.lower() for name in names):
            raise RuntimeError("Unexpected system overlay or LSPosed payload")
    return digest, archive.stat().st_size


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--zip", type=Path, required=True, help="Prepared disabled experiment ZIP")
    p.add_argument("--sha256", required=True, help="Exact ZIP SHA-256")
    p.add_argument("--adb", default=None, help="Optional adb executable")
    p.add_argument("--device", default=None, help="ADB serial if more than one device")
    p.add_argument("--check-only", action="store_true", help="Local audit; do not access phone")
    args = p.parse_args()
    digest, size = audit_archive(args.zip, args.sha256)
    print(f"LOCAL_ARCHIVE_VERIFIED sha256={digest} bytes={size}")
    if args.check_only:
        print("CHECK_ONLY_OK (device was not contacted)")
        return

    adb = adb_binary(args.adb)
    devices = run([adb, "devices", "-l"])
    online = [s.split()[0] for s in devices.splitlines()[1:]
              if len(s.split()) >= 2 and s.split()[1] == "device"]
    if args.device:
        if args.device not in online:
            raise RuntimeError(f"Device {args.device} not authorized/online; devices:\n{devices}")
        serial = args.device
    else:
        if len(online) != 1:
            raise RuntimeError(f"Expected exactly one authorized USB device; devices:\n{devices}")
        serial = online[0]

    prefix = [adb, "-s", serial]
    run(prefix + ["shell", "mkdir", "-p", REMOTE_DIR])
    run(prefix + ["push", str(args.zip), REMOTE_ZIP], timeout=120)
    remote_hash = run(prefix + ["shell", "sha256sum", REMOTE_ZIP])
    remote_digest = remote_hash.split()[0].strip().lower()
    if remote_digest != digest:
        raise RuntimeError(f"Device SHA mismatch: {remote_digest} != {digest}")
    print(f"DEVICE_ARCHIVE_VERIFIED serial={serial} sha256={remote_digest}")
    print(f"STAGED_ONLY path={REMOTE_ZIP} (NOT INSTALLED, NO REBOOT, MODULE INACTIVE)")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired, zipfile.BadZipFile) as exc:
        print(f"STAGING_REFUSED: {exc}", file=sys.stderr)
        sys.exit(2)
