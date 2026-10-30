#!/usr/bin/env python3
"""Host-only cross-ROM policy tests. Never install or inject anything."""
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
out = root / "build" / "host-test"
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
source = sorted((root / "src").rglob("*.java"))
source = [p for p in source if p.name != "PowerKeeperRuntimeEntry.java"]
tests = sorted((root / "test").rglob("*.java"))
subprocess.run(["javac", "--release", "8", "-d", str(out), *map(str,source),
                *map(str, tests)], check=True)
subprocess.run(["java", "-cp", str(out),
                "io.github.e3n.fcmu.pk.PowerKeeperRuntimePolicyTest"], check=True)
print("POWERKEEPER_RUNTIME_POLICY_TESTS_PASS")
