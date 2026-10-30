#!/usr/bin/env python3
"""Package an INERT, opt-in Zygisk PowerKeeper experiment from trusted CI binaries.

This is not a release. The archive is disabled by default and deliberately
contains no Magisk base FCM workers, no LSPosed bridge and no system overlay.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import zipfile

MODULE = "fcmu_pk_experiment"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--ci-zip", type=Path, required=True)
    p.add_argument("--ci-sha256", required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    digest = hashlib.sha256(args.ci_zip.read_bytes()).hexdigest()
    if digest != args.ci_sha256.lower():
        raise SystemExit(f"Untrusted CI artifact SHA: {digest}")

    with zipfile.ZipFile(args.ci_zip) as source:
        binary = source.read("build/native/libfcmu_pk.so")
        dex = source.read("build/powerkeeper-runtime.dex")
        test_binary = source.read("build/native/libfcmu_pk_selftest.so")
        assert binary[:4] == b"\x7fELF" and len(binary) > 1_000_000
        assert dex[:4] == b"dex\n" and len(dex) > 1000
        assert binary != test_binary

    module_prop = f"""id={MODULE}
name=FCMU PowerKeeper ART Scoped Experiment [DISABLED]
version=0.0.1-test
versionCode=1
author=E3N
description=Disabled by default; experimental PowerKeeper-only ART Hook; not a stable FCM module
"""
    # A second attempted boot is automatically disabled by the pre-zygote
    # stage; no blocking waits or external Binder/services at post-fs-data.
    postfs = """#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/adb/fcmu_pk_experiment
mkdir -p "$STATE"
if [ -f "$STATE/boot_attempt" ]; then
  touch "$MODDIR/disable"
  echo "second boot attempt: module disabled" > "$STATE/rollback.log"
  exit 0
fi
cat /proc/sys/kernel/random/boot_id > "$STATE/boot_attempt"
echo "first boot armed" > "$STATE/boot.log"
exit 0
"""
    # Opt-out is set even when boot succeeds, so a future restart is not an
    # unintentional second experiment. The script is short-lived, not a daemon.
    service = """#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/adb/fcmu_pk_experiment
mkdir -p "$STATE"
sleep 25
{
  echo "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
  echo "boot_completed=$(getprop sys.boot_completed)"
  echo "pk_pid=$(pidof com.miui.powerkeeper com.xiaomi.powerkeeper)"
  echo "gms_pid=$(pidof com.google.android.gms)"
  echo "gms_tcp_5228=$(ss -tn 2>/dev/null | grep -c ':5228')"
} > "$STATE/boot_observation.txt"
touch "$MODDIR/disable"
echo "one-shot completed; module disabled for next boot" >> "$STATE/boot_observation.txt"
exit 0
"""
    uninstall = """#!/system/bin/sh
exit 0
"""
    files = {
        "module.prop": module_prop.encode(),
        "disable": b"",
        "skip_mount": b"",
        "zygisk/arm64-v8a.so": binary,
        "powerkeeper-runtime.dex": dex,
        "backend/powerkeeper-packages.list": b"com.miui.powerkeeper\ncom.xiaomi.powerkeeper\n",
        "backend/powerkeeper-capabilities.tsv": b"pk.equivalence\tunverified\tno installed OEM hooks asserted\n",
        "post-fs-data.sh": postfs.encode(),
        "service.sh": service.encode(),
        "uninstall.sh": uninstall.encode(),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as out:
        for name, content in files.items():
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            out.writestr(info, content)
    with zipfile.ZipFile(args.out) as audit:
        assert set(audit.namelist()) == set(files)
        assert audit.read("disable") == b""
        assert not any("lsposed" in name.lower() or name.startswith("system/") for name in files)
    print(f"SCOPED_EXPERIMENT_DISABLED_PACKAGE_OK {args.out}")
    print(f"SOURCE_CI_SHA256 {digest}")
    print(f"PACKAGE_SHA256 {hashlib.sha256(args.out.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
