#!/usr/bin/env python3
"""Build the static experiment from a local JDK + Android SDK; never use proxies."""
import argparse, hashlib, os, pathlib, shutil, subprocess, zipfile
ROOT = pathlib.Path(__file__).resolve().parent
def run(args):
    subprocess.run([str(x) for x in args], check=True)
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sdk", required=True)
    p.add_argument("--jdk", required=True)
    a = p.parse_args()
    sdk, jdk = pathlib.Path(a.sdk), pathlib.Path(a.jdk)
    suffix = ".exe" if os.name == "nt" else ""
    javac, java = jdk/"bin"/("javac"+suffix), jdk/"bin"/("java"+suffix)
    libs = []
    for prefix in ("smali-dexlib2-", "smali-util-", "guava-"):
        found = sorted((sdk/"cmdline-tools").rglob(prefix+"*.jar"))
        if not found:
            raise SystemExit("Missing SDK dependency: "+prefix)
        libs.append(found[-1])
    platforms = sorted((sdk/"platforms").glob("android-*/android.jar"))
    d8s = sorted((sdk/"build-tools").glob("*/lib/d8.jar"))
    if not platforms or not d8s: raise SystemExit("Missing Android platform or d8")
    out = ROOT/"build"
    classes, policy = out/"patcher-classes", out/"policy-classes"
    for d in (classes, policy):
        if d.exists(): shutil.rmtree(d)
        d.mkdir(parents=True)
    package = ROOT/"src/io/github/e3n/fcmu"
    run([javac, "--release", "8", "-cp", os.pathsep.join(map(str, libs)), "-d", classes, package/"Patcher.java", package/"Adaptive.java", package/"PowerKeeperProbe.java"])
    run([javac, "--release", "8", "-cp", platforms[-1], "-d", policy, package/"StaticPolicy.java"])
    run([java, "-cp", d8s[-1], "com.android.tools.r8.D8", "--min-api", "26", "--lib", platforms[-1], "--output", out/"policy.jar", *policy.rglob("*.class")])
    with zipfile.ZipFile(out/"policy.jar") as z:
        (out/"policy.dex").write_bytes(z.read("classes.dex"))
    verify = out/"verify-classes"
    verify.mkdir(exist_ok=True)
    run([javac, "--release", "8", "-cp", platforms[-1], "-d", verify, package/"Verify.java"])
    run([java, "-cp", d8s[-1], "com.android.tools.r8.D8", "--min-api", "26", "--lib", platforms[-1], "--output", out/"verify.jar", *verify.rglob("*.class")])
    run([java, "-cp", d8s[-1], "com.android.tools.r8.D8", "--min-api", "26", "--lib", platforms[-1], "--output", out/"patcher.jar", *classes.rglob("*.class"), *libs])
    with zipfile.ZipFile(out/"patcher-host.jar", "w", zipfile.ZIP_DEFLATED) as dst:
        seen = set()
        for lib in libs:
            with zipfile.ZipFile(lib) as src:
                for name in src.namelist():
                    if name.endswith(".class") and name not in seen:
                        dst.writestr(name, src.read(name)); seen.add(name)
        for f in classes.rglob("*.class"): dst.write(f, f.relative_to(classes).as_posix())
    for name in ("patcher.jar", "policy.dex"):
        f=out/name
        print(name, f.stat().st_size, hashlib.sha256(f.read_bytes()).hexdigest())
if __name__ == "__main__": main()
