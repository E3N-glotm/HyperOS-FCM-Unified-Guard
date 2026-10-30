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
    text=text.replace("cat /proc/sys/kernel/random/boot_id",'cat "$TEST_BOOT_ID_FILE"')
    for old,new in [("/system_ext/",str(self.root)+"/system_ext/"),("/system/",str(self.root)+"/system/"),("/product/",str(self.root)+"/product/"),("/data/adb/",str(self.root)+"/data/adb/")]:text=text.replace(old,new)
    dest.write_text(text,encoding="utf-8");dest.chmod(0o755)
  (self.mod/"tools").mkdir()
  for name in ["policy.dex","patcher.jar","verify.jar"]:(self.mod/"tools"/name).write_text(name)
  self.services=self.root/"system/framework/services.jar";self.services.parent.mkdir(parents=True);self.services.write_text("stock-v1")
  self.oem=self.root/"system_ext/framework/miui-services.jar";self.oem.parent.mkdir(parents=True);self.oem.write_text("oem-v1")
  (self.services.parent/"framework.jar").write_text("apis-v1")
  (self.mod/"bin/runtime_workers.sh").write_text("worker_ticks() { echo 456; }\n")
  (self.mod/"bin/deviceidle_policy.sh").write_text("exit 0\n")
  (self.mod/"core-service.sh").write_text('echo core-started > "$FCM_UNIFIED_RUNTIME/core-started"\n')
  self.boot_number=0;self.boot_file=self.root/"boot-id";self.boot_file.write_text("test-boot-0\n")
  self.env=dict(os.environ,PATH=str(self.bin)+os.pathsep+os.environ["PATH"],FCM_UNIFIED_RUNTIME=str(self.run),MODPATH=str(self.mod),MODE="full",SYSTEMSERVERCLASSPATH="",TEST_SERVICES=str(self.services),TEST_BOOT_ID_FILE=str(self.boot_file),KEYS=" ".join(KEYS))
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
 io.github.e3n.fcmu.PowerKeeperProbe)
  shift
  [ "$1" = "$TEST_PK_APK" ] || exit 7
  printf 'pk.apk\tpresent\tinspectable_apks=1;failed=0\n'
  printf 'pk.gms.framework\tpresent\tverified signature only\n'
  printf 'pk.equivalence\tunverified\tno hook installed\n'
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
 def advance_boot(self):
  self.boot_number+=1;self.boot_file.write_text(f"test-boot-{self.boot_number}\n")
 def boot(self):
  self.advance_boot();self.env["MODE"]="full";self.script("post-fs-data.sh")
 def health(self,mode="full"):
  self.env["MODE"]=mode;self.script("bin/health_status.sh","--fresh")
  return (self.run/"health-summary.txt").read_text()
 def test_powerkeeper_missing_apk_does_not_disable_fcm(self):
  self.tool("pm","exit 1\n")
  self.script("bin/powerkeeper_probe.sh")
  diag=(self.mod/"backend/powerkeeper-capabilities.tsv").read_text()
  self.assertIn("pk.apk\tunknown",diag)
  self.assertIn("pk.equivalence\tunverified",diag)
  self.assertFalse((self.mod/"disable").exists())
  self.assertFalse((self.mod/"remove").exists())
 def test_powerkeeper_dynamic_apk_is_detected_without_rom_gates(self):
  path=self.root/"vendor-app"/"PowerKeeper.apk";path.parent.mkdir(parents=True)
  path.write_text("sample")
  self.env["TEST_PK_APK"]=str(path)
  self.tool("pm",'''case "$1" in path) echo "package:$TEST_PK_APK";; esac\n''')
  self.script("bin/powerkeeper_probe.sh")
  diag=(self.mod/"backend/powerkeeper-capabilities.tsv").read_text()
  self.assertIn("pk.gms.framework\tpresent",diag)
  self.assertIn("pk.equivalence\tunverified",diag)
  self.assertFalse((self.mod/"disable").exists())
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
  self.assertEqual(self.state(),"MOUNTED");self.script("service.sh")
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
 def test_cached_health_stale_connected_recovers_without_waiting_next_poll(self):
  self.build();self.boot();self.script("service.sh")
  cache=self.run/"fcm-observed.state"
  cache.write_text("unknown 1\n")
  self.script("bin/health_status.sh","--cached")
  self.assertIn("FCM在线",(self.run/"health-summary.txt").read_text())
  self.assertIn("GREEN\tFCM",(self.run/"health-status.txt").read_text())
  self.assertEqual(cache.read_text(),"unknown 1\n","health check must not overwrite guard-owned cache")
 def test_cached_health_stale_disconnected_is_not_false_green(self):
  self.build();self.boot();self.script("service.sh")
  cache=self.run/"fcm-observed.state";cache.write_text("connected 1\n")
  self.env["MODE"]="disconnected"
  self.script("bin/health_status.sh","--cached")
  self.assertIn("FCM断开",(self.run/"health-summary.txt").read_text())
  self.assertIn("RED\tFCM",(self.run/"health-status.txt").read_text())
 def test_cached_health_no_gms_diagnostics_stays_unknown(self):
  self.build();self.boot();self.script("service.sh")
  cache=self.run/"fcm-observed.state";cache.write_text("connected 1\n")
  self.tool("dumpsys",r"""
case "$1" in
 activity) :;;
 greezer) echo 'mGmsLimitEnabled : false';;
esac
""")
  self.script("bin/health_status.sh","--cached")
  self.assertIn("FCM未知",(self.run/"health-summary.txt").read_text())
  self.assertIn("YELLOW\tFCM",(self.run/"health-status.txt").read_text())
 def test_cached_health_recent_observation_avoids_extra_probe(self):
  self.build();self.boot();self.script("service.sh")
  cache=self.run/"fcm-observed.state"
  now=int(__import__("time").time());cache.write_text(f"connected {now}\n")
  counter=self.run/"fcm-extra-probe"
  self.env["TEST_PROBE_COUNTER"]=str(counter)
  self.tool("dumpsys",r"""
case "$1" in
 activity) echo query >> "$TEST_PROBE_COUNTER"; echo 'Is client connected: false';;
 greezer) echo 'mGmsLimitEnabled : false';;
esac
""")
  self.script("bin/health_status.sh","--cached")
  self.assertIn("FCM在线",(self.run/"health-summary.txt").read_text())
  self.assertFalse(counter.exists(),"fresh cache must not run a second GMS query")
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
 def test_boot_replaces_previous_reboot_notice_before_health(self):
  self.build();self.health();self.assertIn("待重启生效",(self.mod/"module.prop").read_text())
  self.boot()
  description=(self.mod/"module.prop").read_text()
  self.assertNotIn("待重启",description)
  self.assertIn("框架已挂载",description);self.assertIn("无需再次重启",description)
 def test_mount_failure_replaces_previous_reboot_notice_immediately(self):
  self.build();self.health();self.advance_boot();self.env["MODE"]="mount-fail"
  self.script("post-fs-data.sh")
  description=(self.mod/"module.prop").read_text()
  self.assertNotIn("待重启",description);self.assertIn("适配异常",description)
 def test_stale_ready_from_previous_boot_does_not_request_reboot(self):
  self.build();self.health();self.advance_boot()
  summary=self.health()
  self.assertNotIn("待重启",summary)
  self.assertIn("正在检查本次启动",summary)
  self.assertNotIn("next normal reboot required",(self.run/"health-status.txt").read_text())
 def test_service_resets_stale_notice_before_starting_core(self):
  self.build();self.health();self.advance_boot()
  (self.mod/"core-service.sh").write_text('cp "${0%/*}/module.prop" "$FCM_UNIFIED_RUNTIME/core-entry.prop"\n')
  self.script("service.sh")
  description=(self.run/"core-entry.prop").read_text()
  self.assertNotIn("待重启",description);self.assertIn("正在检查本次启动",description)
 def test_current_boot_ready_still_requests_one_reboot(self):
  self.build();self.assertIn("待重启生效",self.health())
  self.assertIn("next normal reboot required",(self.run/"health-status.txt").read_text())
 def test_new_generation_does_not_lose_its_reboot_request(self):
  self.build();self.boot();self.script("service.sh")
  (self.mod/"tools/patcher.jar").write_text("new-generator")
  self.script("bin/build_backend.sh","retry")
  self.assertIn("待重启生效",self.health())
 def test_mounted_backend_waits_for_ack_without_reboot_request(self):
  self.build();self.boot()
  summary=self.health()
  self.assertIn("框架已挂载",summary);self.assertIn("无需再次重启",summary)
  self.assertIn("🟡",summary);self.assertNotIn("待重启",summary)
 def test_active_state_without_actual_payload_does_not_claim_loaded(self):
  self.build();self.boot();self.script("service.sh")
  self.services.write_text("stock-v1");self.oem.write_text("oem-v1")
  summary=self.health()
  self.assertIn("🔴",summary);self.assertNotIn("框架已加载",summary)
 def test_powerkeeper_signature_count_excludes_apk_and_class_metadata(self):
  self.build();self.boot();self.script("service.sh")
  path=self.mod/"backend/powerkeeper-capabilities.tsv"
  path.write_text("pk.apk\tpresent\tinspectable_apks=1\n"
   "pk.gms.observer\tpresent\tclass\n"
   "pk.gms.alarm\tpresent\tmethod\n"
   "pk.gms.network\tpresent\tmethod\n"
   "pk.gms.binder_chain\tpresent\tmetadata\n"
   "pk.gms.wakelock\tvariant\tother overload\n"
   "pk.equivalence\tunverified\tnot active\n")
  self.health()
  report=(self.run/"health-status.txt").read_text()
  self.assertIn("1 detected method signatures, 1 variants",report)
  self.assertIn("0 PowerKeeper runtime hooks enabled",report)
  self.assertNotIn("4 matching signatures",report)
 def test_action_active_backend_reports_actual_cached_capabilities(self):
  self.build();self.boot();self.script("service.sh")
  (self.mod/"backend/last-capabilities.tsv").unlink(missing_ok=True)
  result=self.script("action.sh")
  self.assertEqual(self.state(),"ACTIVE")
  self.assertIn("当前框架缓存:",result.stdout)
  self.assertIn("ams.broadcast",result.stdout)
  self.assertNotIn("capabilities.tsv unavailable; generation may have failed",result.stdout)
  self.assertIn("历史记录，并非当前故障",result.stdout)
  self.assertIn("框架10/10",(self.run/"health-summary.txt").read_text())
 def test_action_report_uses_previous_generation_only_as_labelled_fallback(self):
  self.build();self.boot();self.script("service.sh")
  (self.cache()/"capabilities.tsv").unlink()
  report=self.mod/"backend/last-capabilities.tsv"
  report.write_text("ams.broadcast\tready\told-generated-only\n")
  result=self.script("action.sh")
  self.assertIn("上次生成记录（不代表当前已加载）",result.stdout)
  self.assertIn("old-generated-only",result.stdout)
 def test_action_probes_powerkeeper_before_health_report(self):
  self.build();self.boot();self.script("service.sh")
  result=self.script("action.sh")
  self.assertIn("PowerKeeper 动态接口探测",result.stdout)
  self.assertIn("POWERKEEPER",result.stdout)
  self.assertIn("read-only APK probe:",result.stdout)
 def test_action_on_active_backend_keeps_generation(self):
  self.build();self.boot();self.script("service.sh")
  before=(self.mod/"backend/current").read_text();self.script("action.sh")
  self.assertEqual((self.mod/"backend/current").read_text(),before)
  self.assertEqual(self.state(),"ACTIVE");self.assertIn("框架已加载",(self.mod/"module.prop").read_text())
 def test_action_on_mounted_backend_does_not_skip_ack(self):
  self.build();self.boot();self.script("action.sh")
  self.assertEqual(self.state(),"MOUNTED");self.assertTrue((self.mod/"backend/pending").exists())
  self.assertNotIn("待重启",(self.mod/"module.prop").read_text())
  (self.cache()/"source/services.jar").unlink();(self.mod/"tools/patcher.jar").write_text("new-generator")
  self.script("action.sh")
  self.assertEqual(self.state(),"MOUNTED");self.assertTrue((self.mod/"backend/pending").exists())
 def test_action_on_ready_cache_does_not_regenerate(self):
  self.build();before=(self.mod/"backend/current").read_text();self.script("action.sh")
  self.assertEqual((self.mod/"backend/current").read_text(),before);self.assertEqual(self.state(),"READY")
 def test_action_retries_failed_generation(self):
  self.env["MODE"]="generation-fail";self.script("bin/build_backend.sh","auto",ok=False)
  self.env["MODE"]="full";self.script("action.sh")
  self.assertEqual(self.state(),"READY");self.assertTrue((self.mod/"backend/current").exists())


 def test_no_greeze_dumpsys_still_reports_whitelist(self):
  self.tool("dumpsys",r"""
case "$1" in
 activity) echo 'Is client connected: true';;
 greezer) :;;
esac
""")
  self.health()
  report=(self.run/"health-status.txt").read_text()
  self.assertIn("GREEN\tMILLET",report)
  self.assertIn("GRAY\tGMS_LIMIT",report)

 def test_missing_feature_report_is_unknown_not_zero_of_zero(self):
  self.env["MODE"]="generation-fail"
  self.script("bin/build_backend.sh","retry",ok=False)
  summary=self.health()
  self.assertIn("框架未知",summary)
  self.assertNotIn("框架0/0",summary)
  report=(self.run/"health-status.txt").read_text()
  self.assertIn("backend/build.log",report)
  self.assertIn("RED\tBACKEND",report)

if __name__=="__main__":
 if os.name=="nt":
  print("SKIP native-path simulation on Windows; Linux CI runs all runtime/OTA/status scenarios")
 else:
  parser=argparse.ArgumentParser();parser.add_argument("--group",default="all");opts,rest=parser.parse_known_args()
  unittest.main(argv=[__file__,*rest],verbosity=2)
