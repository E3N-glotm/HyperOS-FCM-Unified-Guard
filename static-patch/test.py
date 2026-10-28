#!/usr/bin/env python3
import argparse, pathlib, os, subprocess
ROOT=pathlib.Path(__file__).resolve().parent
def run(args): subprocess.run([str(x) for x in args], check=True)
def main():
 p=argparse.ArgumentParser();p.add_argument("--sdk",required=True);p.add_argument("--jdk",required=True);a=p.parse_args()
 sdk,jdk=pathlib.Path(a.sdk),pathlib.Path(a.jdk);suffix=".exe" if os.name=="nt" else ""
 javac,java=jdk/"bin"/("javac"+suffix),jdk/"bin"/("java"+suffix)
 out=ROOT/"build/policy-tests";out.mkdir(parents=True,exist_ok=True)
 run([javac,"--release","8","-d",out,*list((ROOT/"test-policy").rglob("*.java")),ROOT/"src/io/github/e3n/fcmu/StaticPolicy.java"])
 run([java,"-cp",out,"PolicyTest"])
 libs=[]
 for prefix in ("smali-dexlib2-","smali-util-","guava-"):libs.append(sorted((sdk/"cmdline-tools").rglob(prefix+"*.jar"))[-1])
 cp=os.pathsep.join(map(str,libs+[ROOT/"build/patcher-classes"]))
 run([javac,"--release","8","-cp",cp,"-d",out,*list((ROOT/"test-patcher").glob("*.java"))])
 run([java,"-cp",os.pathsep.join([str(out),cp]),"io.github.e3n.fcmu.PatcherTest"])
 run([java,"-cp",os.pathsep.join([str(out),cp]),"io.github.e3n.fcmu.CapabilityTest"])
if __name__=="__main__":main()
