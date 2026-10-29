#!/usr/bin/env python3
"""Package a standalone candidate without an APK, LSPosed or Zygisk payload."""
import hashlib, pathlib, zipfile
ROOT=pathlib.Path(__file__).resolve().parent
repo=ROOT.parent
out=repo/"dist";out.mkdir(exist_ok=True)
version=next(line.split("=",1)[1] for line in (ROOT/"overlay/module.prop").read_text(encoding="utf-8").splitlines() if line.startswith("version="))
target=out/f"HyperOS-FCM-Unified-Guard-v{version}-static.zip"
files={}
for p in (repo/"module").rglob("*"):
 if not p.is_file():continue
 rel=p.relative_to(repo/"module").as_posix()
 if rel.startswith("bridge/") or rel in {"bin/bridgectl","bin/bridge_status.sh"}:continue
 data=p.read_bytes()
 if rel=="service.sh":
  text=data.decode().replace('/system/bin/sh "$MODDIR/bin/bridge_status.sh" > "$RUNDIR/bridge-status.txt" 2>&1 || true\n',"")
  text=text.replace("ACTIVE: unified core; bridge registration tracked separately in bridge-status.txt","ACTIVE: adaptive guard core (framework state tracked separately)")
  files["core-service.sh"]=text.encode()
  continue
 files[rel]=data
for p in (ROOT/"overlay").rglob("*"):
 if p.is_file():files[p.relative_to(ROOT/"overlay").as_posix()]=p.read_bytes()
for name in ("patcher.jar","policy.dex","verify.jar"):
 files["tools/"+name]=(ROOT/"build"/name).read_bytes()
files["LICENSES/FCM-Live-GPL-3.0.txt"]=(repo/"bridge-source/LICENSE").read_bytes()
files["LICENSES/Unified-Core-MIT.txt"]=(repo/"LICENSE").read_bytes()
files["STATIC_EXPERIMENT.md"]=(ROOT/"README.md").read_bytes()
with zipfile.ZipFile(target,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for name,data in sorted(files.items()):
  if name.endswith((".sh",".conf",".prop",".md")) or name=="bin/milletctl":data=data.replace(b"\r\n",b"\n")
  info=zipfile.ZipInfo(name,date_time=(2026,10,29,0,0,0))
  info.compress_type=zipfile.ZIP_DEFLATED
  info.external_attr=(0o100755 if name.endswith(".sh") or name=="bin/milletctl" else 0o100644)<<16
  z.writestr(info,data)
with zipfile.ZipFile(target) as z:
 names=z.namelist()
 assert "skip_mount" in names and "post-fs-data.sh" in names and "core-service.sh" in names
 assert not any(n.endswith(".apk") or n.startswith(("zygisk/","bridge/","patched/")) for n in names)
 for n in names:
  if n.endswith(".sh"):assert b"\r" not in z.read(n),n
digest=hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix(".zip.sha256").write_text(digest+"  "+target.name+"\n",encoding="ascii")
print(target);print("SHA256",digest);print("ZIP contents PASS: no APK / LSPosed bridge / Zygisk / prebuilt Xiaomi JAR")
