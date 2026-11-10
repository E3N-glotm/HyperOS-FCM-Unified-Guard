#!/usr/bin/env python3
"""alpha20: only confirmed faults are yellow; missing evidence remains neutral.

This test executes the actual emit() and summary decision extracted from the
release source as a host POSIX sh process, as well as checking the live and
legacy-overlay scripts for each user-visible false-warning regression.
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
current = (root / "module/bin/health_status.sh").read_text(encoding="utf-8")
legacy = (root / "static-patch/overlay/bin/health_status.sh").read_text(encoding="utf-8")
common = (root / "static-patch/overlay/bin/static_common.sh").read_text(encoding="utf-8")

for label, source in (("active", current), ("legacy-overlay", legacy)):
    checks = {
        "unknown current FCM is gray, not confirmed disconnected":
            'emit GRAY FCM "connection diagnostics unavailable or stale; no disconnect proven"' in source
            and 'disconnected) emit RED FCM' in source,
        "unverified PowerKeeper mapping is gray, not a global yellow":
            'emit GRAY POWERKEEPER "native Zygisk mapped;' in source
            and 'emit GRAY POWERKEEPER "runtime bundled;' in source,
        "explicit OEM quarantine remains yellow":
            'emit YELLOW POWERKEEPER "native runtime quarantined' in source,
        "unknown deviceidle output is gray while confirmed absence is yellow":
            'emit GRAY DEVICEIDLE "native GMS exemption status unavailable' in source
            and 'emit YELLOW DEVICEIDLE "native GMS exemption absent' in source,
        "pending framework backend is gray, explicit errors remain red":
            '*) emit GRAY BACKEND "$detail"' in source
            and 'ERROR|QUARANTINED) emit RED BACKEND' in source
            and "backend_unverified=1" in source,
        "pending next reboot and missing report are gray":
            'emit GRAY "$feature" "generated; next normal reboot required' in source
            and 'emit GRAY "$feature" "cached; current-boot validation pending' in source
            and 'emit GRAY FEATURES "feature report unavailable' in source,
        "explicit failed features still show yellow":
            'failed|failure|error) emit YELLOW "$feature"' in source,
        "level aggregation preserves gray neutrality":
            'GREEN) verified_count=$((verified_count+1))' in source
            and 'GRAY) unknown_count=$((unknown_count+1))' in source,
        "top yellow label refers to confirmed defect, not adaptation":
            "label='已确认部分功能异常'" in source
            and "label='部分功能/适配中'" not in source,
    }
    for name, passed in checks.items():
        if not passed:
            raise AssertionError(f"{label}: {name}")
        print("PASS", label, name)

for label, passed in {
    "scheduled kernel wake not yet observed is gray":
        'emit GRAY WAKEUP "kernel alarm helper installed; first scheduled wake not observed yet"' in current,
    "confirmed kernel alarm failure remains yellow":
        'fallback-sleep*) emit YELLOW WAKEUP' in current,
    "PowerKeeper audit with no method evidence is gray":
        'emit GRAY PK_METHODS "GmsObserver/Doze' in current
        and 'emit GRAY PK_DNS_HIT "DNS method install observed' in current
        and 'emit GRAY PK_DNS_HOOK "No current-boot PID-matched' in current,
    "confirmed OEM DNS initial allow failure stays yellow":
        'dns_initial_allow=failed*|dns_initial_allow=error*) emit YELLOW PK_DNS_HOOK' in current,
    "all other unverified initial allow states gray":
        '*) emit GRAY PK_DNS_HOOK "GMS-only DNS hook installed' in current,
    "boot phase no longer overwrites green as warning":
        "*) bstatus_lamp='⚪'" in common
        and "ERROR|QUARANTINED) bstatus_lamp='🔴'" in common
        and "bstatus_lamp='🟡'" not in common,
}.items():
    if not passed:
        raise AssertionError(label)
    print("PASS", label)

# Execute actual sh functions and shell summary case to validate precedence.
def scenario(events, expected_lamp):
    with tempfile.TemporaryDirectory(prefix="health-alpha20-") as directory:
        emitter = current.split("emit() {", 1)[1].split("\n}\n", 1)[0]
        assert "case" in emitter
        emitter = "emit() {" + emitter + "\n}"
        summary_start = current.rindex('case "$level" in')
        summary_end = current.index("\nphase_label=", summary_start)
        summary = current[summary_start:summary_end]
        emissions = "\n".join(f'emit {state} {name} "simulated"' for state, name in events)
        cmd = (
            f'OUT="{directory}/events"; level=0; verified_count=0; unknown_count=0;\n'
            + emitter + "\n" + emissions + "\n" + summary
            + '\nprintf "%s\\n" "$lamp"'
        )
        result = subprocess.run(["sh", "-c", cmd], text=True,
                                capture_output=True, timeout=5, check=True)
        lamp = result.stdout.strip().splitlines()[-1]
        assert lamp == expected_lamp, (events, lamp, result.stderr)
        print("PASS", "aggregate", events, "=>", lamp)

scenario([("GRAY", "POWERKEEPER"), ("GRAY", "FCM")], "⚪")
scenario([("GREEN", "CORE"), ("GRAY", "POWERKEEPER")], "🟢")
scenario([("GREEN", "CORE"), ("GREEN", "FCM")], "🟢")
scenario([("GRAY", "POWERKEEPER"), ("YELLOW", "GMS_LIMIT")], "🟡")
scenario([("GREEN", "CORE"), ("YELLOW", "MILLET")], "🟡")
scenario([("RED", "FCM"), ("YELLOW", "MILLET")], "🔴")

print("ALPHA20_EVIDENCE_ONLY_HEALTH_AND_BOOT_SUMMARY_PASS")
