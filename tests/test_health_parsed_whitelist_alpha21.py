#!/usr/bin/env python3
"""alpha21: malformed/unsupported OEM list output must NEVER trigger yellow.

Execute the actual settings / deviceidle decision blocks from both shipped and
legacy-overlay health scripts in a POSIX shell with isolated mocked command
outputs. No Android device, root operations, Magisk, or Box access is needed.
"""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
scripts = {
    "active": (root/"module/bin/health_status.sh").read_text(),
    "legacy": (root/"static-patch/overlay/bin/health_status.sh").read_text(),
}

def invoke(source: str, command: str, value: str) -> str:
    if command == "MILLET":
        start = source.index("# Greeze dumpsys and SettingsProvider")
        end = source.index("# The static backend", start)
        fragment = source[start:end]
    else:
        start = source.index("idle=$(probe5 cmd deviceidle whitelist")
        end = source.index("backend_read_state\nmounted=0", start)
        fragment = source[start:end]
    # Command response substitution must not have any external side effects.
    harness = (
        "probe5() { printf '%s\\n' \"$MOCK_REPLY\"; }\n"
        "emit() { printf '%s\\t%s\\n' \"$1\" \"$2\"; }\n"
        + fragment
    )
    result = subprocess.run(
        ["sh", "-c", harness], capture_output=True, text=True,
        env={**os.environ, "MOCK_REPLY": value}, timeout=5, check=True
    )
    return result.stdout.strip().splitlines()[-1].split("\t")[0]

tests = [
    ("MILLET", "com.google.android.gms", "GREEN"),
    ("MILLET", "com.example.other,com.google.android.gms", "GREEN"),
    ("MILLET", "com.example.other,com.another.app", "YELLOW"),
    ("MILLET", "Help: system setting syntax", "GRAY"),
    ("MILLET", "Permission denial: requires android.permission.WRITE_SECURE_SETTINGS", "GRAY"),
    ("MILLET", "Exception from system service", "GRAY"),
    ("MILLET", "null", "GRAY"),
    ("MILLET", "", "GRAY"),
    ("MILLET", "0", "GRAY"),
    ("DEVICEIDLE", "system,com.google.android.gms,10139", "GREEN"),
    ("DEVICEIDLE", "system,com.android.phone,1001\nuser,com.example.other,10199", "YELLOW"),
    ("DEVICEIDLE", "Help: use whitelist options", "GRAY"),
    ("DEVICEIDLE", "Permission denial", "GRAY"),
    ("DEVICEIDLE", "Error: Unknown command", "GRAY"),
    ("DEVICEIDLE", "", "GRAY"),
]
for source_name, source in scripts.items():
    for label, response, expected in tests:
        actual = invoke(source, label, response)
        if actual != expected:
            raise AssertionError((source_name, label, repr(response), actual, expected))
        print("PASS", source_name, label, repr(response), "=>", actual)

print("ALPHA21_CROSS_ROM_WHITELIST_EVIDENCE_ONLY_WARNING_PASS")
