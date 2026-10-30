#!/usr/bin/env python3
"""Compile a disposable app_process driver; artifact is NEVER installable."""
from pathlib import Path
import argparse, subprocess, zipfile
root=Path(__file__).resolve().parent
ap=argparse.ArgumentParser()
ap.add_argument("--sdk",required=True)
ap.add_argument("--jdk",required=True)
args=ap.parse_args()
sdk=Path(args.sdk)
jdk=Path(args.jdk)
platforms=sorted((sdk/"platforms").glob("android-*/android.jar"))
d8=sorted((sdk/"build-tools").glob("*/lib/d8.jar"))
if not platforms or not d8:
    raise SystemExit("Missing Android SDK")
out=root/"build"/"art-init-test"
out.mkdir(parents=True,exist_ok=True)
import os
exe=".exe" if os.name=="nt" else ""
subprocess.run([str(jdk/"bin"/("javac"+exe)),"--release","8","-d",str(out),
 str(root/"test-device"/"ArtInitSelfTest.java")],check=True)
subprocess.run([str(jdk/"bin"/("java"+exe)),"-cp",str(d8[-1]),
 "com.android.tools.r8.D8","--min-api","26","--lib",str(platforms[-1]),
 "--output",str(out),*map(str,sorted(out.glob("ArtInitSelfTest*.class")))],check=True)
with zipfile.ZipFile(root/"build"/"art-init-test.jar","w",compression=zipfile.ZIP_DEFLATED) as jar:
    jar.write(out/"classes.dex","classes.dex")
print("ART_INIT_TEST_DRIVER_BUILT (ISOLATED PROCESS ONLY)")
