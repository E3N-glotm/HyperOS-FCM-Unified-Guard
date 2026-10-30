#!/usr/bin/env python3
"""Build optional bridge DEX for inspection. This does NOT build a Zygisk module."""
import argparse
import pathlib
import subprocess
import shutil
import os
import zipfile

root = pathlib.Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument("--sdk", required=True)
p.add_argument("--jdk", required=True)
args = p.parse_args()
sdk, jdk = pathlib.Path(args.sdk), pathlib.Path(args.jdk)
ext = ".exe" if os.name == "nt" else ""
platform = sorted((sdk / "platforms").glob("android-*/android.jar"))[-1]
d8 = sorted((sdk / "build-tools").glob("*/lib/d8.jar"))[-1]
out = root / "build"
classes = out / "classes"
if classes.exists():
    shutil.rmtree(classes)
classes.mkdir(parents=True)
src = sorted((root / "src").rglob("*.java"))
subprocess.run([str(jdk / "bin" / ("javac" + ext)), "--release", "8", "-cp", str(platform),
                "-d", str(classes), *map(str, src)], check=True)
subprocess.run([str(jdk / "bin" / ("java" + ext)), "-cp", str(d8),
                "com.android.tools.r8.D8", "--min-api", "26", "--lib", str(platform),
                "--output", str(out / "bridge.jar"), *map(str, classes.rglob("*.class"))], check=True)
with zipfile.ZipFile(out / "bridge.jar") as f:
    (out / "powerkeeper-runtime.dex").write_bytes(f.read("classes.dex"))
print("OPTIONAL_BRIDGE_DEX_BUILT (NOT ACTIVATED)", (out / "powerkeeper-runtime.dex").stat().st_size)
