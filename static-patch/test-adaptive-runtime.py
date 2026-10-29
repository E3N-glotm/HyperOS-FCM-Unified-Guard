#!/usr/bin/env python3
"""Control-flow tests with mocked Android/VM/mounts; never a claim of real ART/OTA."""
import argparse, os, pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parent
KEYS="ams.broadcast greeze.allow greeze.defer greeze.limit domestic.defer broadcast.autostart lists.constructor lists.whitelist network.constructor process.whitelist".split()

class RuntimeTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)
  self.mod=self.root/"module";self.run=self.root/"run";self.bin=self.root/"bin"
  self.mod.mkdir();self.run.mkdir();self.bin.mkdir()
  for p in (ROOT/"overlay").rglob("*"):
   if p.is_file():
    dest=self.mod/p.relative_to(ROOT/"overlay");dest.parent.mkdir(parents=True,exist_ok=True)
    text=p.read_text(encoding="utf-8").replace("/system/bin/sh","/bin/sh")
    for old,new in [("/system_ext/",str(self.root)+"/system_ext/"),("/system/",str(self.root)+"/system/"),("/product/",str(self.root)+"/product/"),("/data/adb/",str(self.root)+"/data/adb/")]:text=text.replace(old,new)
    dest.write_text(text,encoding="utf-8");dest.chmod(0o755)
  (self.mod/"tools").mkdir()
  for name in ["policy.dex","patcher.jar","verify.jar"]:(self.mod/"tools"/name).write_text(name)
  self.services=self.root/"system/framework/services.jar";self.services.parent.mkdir(parents=True);self.services.write_text("stock-v1")
  self.oem=self.root/"system_ext/framework/miui-services.jar";self.oem.parent.mkdir(parents=True);self.oem.write_text("oem-v1")
  (self.services.parent/"framework.jar").write_text("apis-v1")
  (self.mod/"bin/runtime_workers.sh").write_text("worker_ticks() { echo 456; }\n")
  (self.mod/"core-service.sh").write_text('echo core-started > "$FCM_UNIFIED_RUNTIME/core-started"\n')
  self.env=dict(os.environ,PATH=str(self.bin)+os.pathsep+os.environ["PATH"],FCM_UNIFIED_RUNTIME=str(self.run),MODPATH=str(self.mod),MODE="full",SYSTEMSERVERCLASSPATH="",TEST_SERVICES=str(self.services),KEYS=" ".join(KEYS))
  self.tool("getprop",'[ "$1" != sys.boot_completed ] || echo 1\n')
  self.tool("sleep","exit 0\n")
  self.tool("chcon","exit 0\n")
  self.tool("dumpsys",r'''
case "$1" in
 activity) if [ "$MODE" = disconnected ]; then echo 'Is client connected: false'; else echo 'Is client connected: true'; fi;;
 greezer) echo 'mGmsLimitEnabled : false';;
esac
''')
  self.tool("settings","echo com.google.android.gms\n")
  self.tool("cmd","echo user,com.google.android.gms,10139\n")
  self.tool("mount",r'''
echo "$*" >> "$FCM_UNIFIED_RUNTIME/mounts"
case "$MODE:$4" in mount-fail:*miui-services.jar) exit 1;; esac
cp "$4" "$4.stock"
cp "$3" "$4"
''')
  self.tool("umount",'cp "$1.stock" "$1"\n')
  self.tool("dalvikvm64",r'''
while [ "$#" -gt 0 ]; do case "$1" in -*) shift;; *) break;; esac; done
case "$1" in
 io.github.e3n.fcmu.Adaptive)
  shift
  if [ "$MODE" = generation-fail ]; then exit 5; fi
  mkdir -p "$4"
  for k in $KEYS; do
   state=ready;reason=ok
   case "$MODE:$k" in none:*|partial:greeze.limit) state=unavailable;reason=missing-interface;; esac
   case ",$5," in *,"$k",*) state=unavailable;reason=runtime-API-missing;; esac
   printf '%s\t%s\t%s\n' "$k" "$state" "$reason"
  done > "$4/capabilities.tsv"
  [ "$MODE" != none ] || exit 1
  printf 'patched:%s\n' "$(cat "$1")" > "$4/services.jar"
  [ "$2" = - ] || printf 'patched:%s\n' "$(cat "$2")" > "$4/miui-services.jar"
  [ "$MODE" != race ] || echo changed-during-build > "$TEST_SERVICES"
  ;;
 io.github.e3n.fcmu.Verify)
  shift
  if [ "$1" = --adaptive ] && [ "$MODE" = art-missing ] && grep -q '^ams.broadcast.ready' "$2"; then
   printf 'VERIFY_FAIL\tams.broadcast\tAPI missing\n';exit 3
  fi
  echo OK;;
 *) exit 6;;
esac
''')
  for name in ["settings","maintenance","events"]:(self.run/(name+".pid")).write_text("123 456\n")
 def tool(self,name,body):
  p=self.bin/name;p.write_text("#!/bin/sh\n"+body);p.chmod(0o755)
 def tearDown(self):self.tmp.cleanup()
 def script(self,name,*args,ok=True):
  result=subprocess.run(["bash",str(self.mod/name),*args],env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=25)
  if ok:self.assertEqual(result.returncode,0,result.stdout)
  return result
 def install(self):
  p=self.root/"install.sh";p.write_text('abort() { echo "ABORT $*"; exit 1; }\nui_print() { :; }\nset_perm_recursive() { :; }\nset_perm() { :; }\n. "$MODPATH/customize.sh"\n')
  r=subprocess.run(["bash",str(p)],env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10)
  self.assertEqual(r.returncode,0,r.stdout)
 def build(self,mode="full"):
  self.env["MODE"]=mode;return self.script("bin/build_backend.sh","retry")
 def state(self):return (self.mod/"backend/state").read_text().split("\t",1)[0]
 def cache(self):return self.mod/"backend"/(self.mod/"backend/current").read_text().strip()
 def boot(self):
  self.env["MODE"]="full";self.script("post-fs-data.sh")
 def health(self,mode="full"):
  self.env["MODE"]=mode;self.script("bin/health_status.sh","--fresh")
  return (self.run/"health-summary.txt").read_text()
 def test_install_missing_vm_and_oem_succeeds(self):
  (self.bin/"dalvikvm64").unlink();self.oem.unlink();self.install()
  self.assertFalse((self.mod/"disable").exists());self.assertTrue((self.run/"packages.list").exists())
 def test_install_preserves_user_configuration(self):
  (self.run/"packages.list").write_text("com.example.user\n")
  (self.run/"unified.conf").write_text("DEVICEIDLE_GMS_POLICY=observe\n")
  self.install();self.assertEqual((self.run/"packages.list").read_text(),"com.example.user\n")
  self.assertIn("observe",(self.run/"unified.conf").read_text())
 def test_boot_without_cache_never_disables(self):
  self.script("post-fs-data.sh");self.assertEqual(self.state(),"DETECT");self.assertFalse((self.mod/"disable").exists())
 def test_service_starts_core_without_backend(self):
  self.env["MODE"]="none";self.script("service.sh")
  self.assertTrue((self.run/"core-started").exists());self.assertEqual(self.state(),"CORE_ONLY")
 def test_full_generation_boot_and_green_status(self):
  self.build();self.assertEqual(self.state(),"READY");self.boot()
  self.assertEqual(self.state(),"ACTIVE");self.assertIn("🟢",self.health())
  self.assertIn("name=HyperOS FCM Unified Guard 🟢",(self.mod/"module.prop").read_text())
 def test_partial_adaptation_is_yellow(self):
  self.build("partial");self.boot();self.assertIn("🟡",self.health())
  self.assertIn("greeze.limit\tmissing-interface",(self.run/"health-status.txt").read_text())
 def test_no_capabilities_remains_installed(self):
  self.build("none");self.assertEqual(self.state(),"CORE_ONLY")
  self.assertFalse((self.mod/"disable").exists());self.assertIn("🟡",self.health())
 def test_disconnection_is_red_with_details(self):
  self.build();self.boot();self.assertIn("🔴",self.health("disconnected"))
  self.assertIn("connection disconnected",(self.run/"health-status.txt").read_text())
 def test_ota_rebuilds_automatically_without_reinstall(self):
  self.build();old=(self.mod/"backend/current").read_text()
  self.services.write_text("stock-v2");self.oem.write_text("oem-v2")
  self.script("post-fs-data.sh");self.assertEqual(self.state(),"REBUILD")
  self.assertFalse((self.run/"mounts").exists());self.assertFalse((self.mod/"disable").exists())
  self.script("bin/build_backend.sh","auto");self.assertEqual(self.state(),"READY")
  self.assertNotEqual((self.mod/"backend/current").read_text(),old)
  self.boot();self.assertIn("patched:stock-v2",self.services.read_text())
 def test_mount_failure_reverts_without_disabling(self):
  self.build();self.env["MODE"]="mount-fail";self.script("post-fs-data.sh")
  self.assertEqual(self.services.read_text(),"stock-v1");self.assertEqual(self.state(),"ERROR")
  self.assertFalse((self.mod/"disable").exists())
 def test_unconfirmed_generation_is_quarantined_only(self):
  self.build();self.boot()
  self.services.write_text("stock-v1");self.oem.write_text("oem-v1")
  self.script("post-fs-data.sh");self.assertEqual(self.state(),"QUARANTINED")
  self.assertFalse((self.mod/"disable").exists())
  self.script("bin/build_backend.sh","auto");self.assertEqual(self.state(),"QUARANTINED")
 def test_art_missing_feature_rebuilds_remaining_features(self):
  self.build("art-missing")
  self.assertEqual(self.state(),"READY")
  self.assertIn("ams.broadcast\tunavailable",(self.cache()/"capabilities.tsv").read_text())
 def test_generation_race_keeps_previous_cache(self):
  self.build();old=(self.mod/"backend/current").read_text()
  self.env["MODE"]="race"
  r=self.script("bin/build_backend.sh","retry",ok=False);self.assertNotEqual(r.returncode,0)
  self.assertEqual(self.state(),"REBUILD")
  self.assertEqual((self.mod/"backend/current").read_text(),old)
  self.assertFalse((self.mod/"disable").exists())
 def test_generation_failure_keeps_previous_cache(self):
  self.build();old=(self.mod/"backend/current").read_text()
  self.env["MODE"]="generation-fail";r=self.script("bin/build_backend.sh","retry",ok=False)
  self.assertNotEqual(r.returncode,0);self.assertEqual((self.mod/"backend/current").read_text(),old)
 def test_single_attempt_per_boot_on_failure(self):
  self.env["MODE"]="generation-fail";self.script("bin/build_backend.sh","auto",ok=False)
  before=(self.mod/"backend/last-attempt").read_text()
  self.script("bin/build_backend.sh","auto");self.assertEqual((self.mod/"backend/last-attempt").read_text(),before)
 def test_retry_with_new_cache_pending_uses_actual_mounted_sources(self):
  self.build();self.boot()
  (self.mod/"tools/patcher.jar").write_text("new-generator")
  self.script("bin/build_backend.sh","retry");self.assertEqual(self.state(),"READY")
  self.script("bin/build_backend.sh","retry");self.assertEqual(self.state(),"READY")
 def test_invalid_security_context_skips_only_framework(self):
  self.build();self.tool("getenforce","echo Enforcing\n")
  self.script("post-fs-data.sh");self.assertEqual(self.state(),"REBUILD")
  self.assertFalse((self.run/"mounts").exists());self.assertFalse((self.mod/"disable").exists())
 def test_wrong_label_cannot_be_accepted_as_ready(self):
  self.tool("getenforce","echo Enforcing\n")
  r=self.script("bin/build_backend.sh","retry",ok=False)
  self.assertNotEqual(r.returncode,0);self.assertEqual(self.state(),"ERROR")
  self.assertFalse((self.mod/"backend/current").exists());self.assertFalse((self.mod/"disable").exists())

if __name__=="__main__":
 if os.name=="nt":
  print("SKIP native-path simulation on Windows; Linux CI runs all runtime/OTA/status scenarios")
 else:
  parser=argparse.ArgumentParser();parser.add_argument("--group",default="all");opts,rest=parser.parse_known_args()
  unittest.main(argv=[__file__,*rest],verbosity=2)
