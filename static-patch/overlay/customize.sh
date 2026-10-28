#!/system/bin/sh
# A static ROM patch is generated locally; no Xiaomi framework is distributed.
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
. "$MODPATH/bin/static_common.sh"
VM=$(find_art_vm) || abort "No executable ART VM found"
SOURCE_SERVICES_PATH=$(readlink -f /system/framework/services.jar) || abort "Missing Android services.jar"
SOURCE_MIUI_PATH=$(discover_oem_jar) || abort "Required OEM framework missing or ambiguous; full FCM policy cannot be installed"
framework_path_ok "$SOURCE_SERVICES_PATH" && framework_path_ok "$SOURCE_MIUI_PATH" || abort "Framework paths are outside system partitions"
SOURCE_SERVICES_SHA256=$(hash_file "$SOURCE_SERVICES_PATH")
SOURCE_MIUI_SHA256=$(hash_file "$SOURCE_MIUI_PATH")
INSTALLED_ROM_SHA256=$(current_rom_identity)
valid_hash "$SOURCE_SERVICES_SHA256" && valid_hash "$SOURCE_MIUI_SHA256" && valid_hash "$INSTALLED_ROM_SHA256" || abort "Cannot identify current framework sources"
ui_print "- Checking this ROM's classes, fields, method signatures and register frames"
CLASSPATH="$MODPATH/tools/patcher.jar" "$VM" -Xmx1024m \
  io.github.e3n.fcmu.Patcher --probe "$SOURCE_SERVICES_PATH" "$SOURCE_MIUI_PATH" \
  > "$MODPATH/install-report.txt" 2>&1 ||
  abort "Incompatible or already-patched framework; see install-report.txt. Disable an older static backend and reboot before reinstalling."
ui_print "- Generating FCM-only framework policy in staging (may take several minutes)"
mkdir "$MODPATH/.staging" || abort "Staging directory already exists or cannot be created"
CLASSPATH="$MODPATH/tools/patcher.jar" "$VM" -Xmx1024m \
  io.github.e3n.fcmu.Patcher "$SOURCE_SERVICES_PATH" "$SOURCE_MIUI_PATH" \
  "$MODPATH/tools/policy.dex" "$MODPATH/.staging" >> "$MODPATH/install-report.txt" 2>&1 ||
  abort "Patch generation rejected; inspect install-report.txt"
ui_print "- Verifying DEX alignment and ART class loading"
CLASSPATH="$MODPATH/tools/verify.jar" "$VM" \
  io.github.e3n.fcmu.Verify --jar "$MODPATH/.staging/services.jar" "$MODPATH/.staging/miui-services.jar" \
  >> "$MODPATH/install-report.txt" 2>&1 || abort "Generated JAR failed ZIP verification"
CLASSPATH="$MODPATH/tools/verify.jar:$MODPATH/.staging/services.jar:$MODPATH/.staging/miui-services.jar:$SYSTEMSERVERCLASSPATH" \
  "$VM" -Xmx512m -Xverify:all io.github.e3n.fcmu.Verify \
  io.github.e3n.fcmu.StaticPolicy com.android.server.am.ActivityManagerService \
  com.android.server.am.BroadcastQueueModernStubImpl com.android.server.am.ProcessPolicy \
  com.miui.server.greeze.GreezeManagerService com.miui.server.greeze.DomesticPolicyManager \
  com.miui.server.greeze.power.ListAppsManager com.miui.server.greeze.power.AwareResourceControl \
  >> "$MODPATH/install-report.txt" 2>&1 || abort "ART rejected the generated policy"
[ "$(hash_file "$SOURCE_SERVICES_PATH")" = "$SOURCE_SERVICES_SHA256" ] &&
[ "$(hash_file "$SOURCE_MIUI_PATH")" = "$SOURCE_MIUI_SHA256" ] &&
[ "$(current_rom_identity)" = "$INSTALLED_ROM_SHA256" ] || abort "ROM changed during generation; nothing accepted"
mv "$MODPATH/.staging" "$MODPATH/patched" || abort "Cannot accept generated framework pair"
{
  echo PROFILE_FORMAT=2
  echo "SOURCE_SERVICES_PATH=$SOURCE_SERVICES_PATH"
  echo "SOURCE_MIUI_PATH=$SOURCE_MIUI_PATH"
  echo "SOURCE_SERVICES_SHA256=$SOURCE_SERVICES_SHA256"
  echo "SOURCE_MIUI_SHA256=$SOURCE_MIUI_SHA256"
  echo "INSTALLED_ROM_SHA256=$INSTALLED_ROM_SHA256"
  echo "PATCHED_SERVICES_SHA256=$(hash_file "$MODPATH/patched/services.jar")"
  echo "PATCHED_MIUI_SHA256=$(hash_file "$MODPATH/patched/miui-services.jar")"
} > "$MODPATH/profile.conf"
. "$MODPATH/profile.conf"
profile_valid || abort "Incomplete generated compatibility profile"
mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
stamp=$(date +%Y%m%d_%H%M%S)
mkdir -p "$RUNDIR/backups/static-$stamp"
for f in packages.list managed.last unified.conf; do
  [ ! -f "$RUNDIR/$f" ] || cp -p "$RUNDIR/$f" "$RUNDIR/backups/static-$stamp/$f"
done
# Import the current legacy configuration before its uninstall cleanup runs.
if [ -f /data/adb/millet_guard/packages.list ]; then
  cp -p /data/adb/millet_guard/packages.list "$RUNDIR/packages.list"
fi
[ -f "$RUNDIR/packages.list" ] || printf '%s\n' com.google.android.gms > "$RUNDIR/packages.list"
# Replace PowerKeeper's effective GMS Doze exemption through the native user list.
# The ownership-aware DeviceIdle tool preserves exemptions that predate this module.
conf="$RUNDIR/unified.conf"
[ -f "$conf" ] || : > "$conf"
sed '/^DEVICEIDLE_GMS_POLICY=/d' "$conf" > "$conf.new"
printf '%s\n' DEVICEIDLE_GMS_POLICY=enforce >> "$conf.new"
mv "$conf.new" "$conf"
chmod 600 "$conf" "$RUNDIR/packages.list"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH/"*.sh "$MODPATH/bin/"*.sh "$MODPATH/bin/milletctl"; do
  [ ! -f "$f" ] || set_perm "$f" 0 0 0755
done
chcon u:object_r:system_file:s0 "$MODPATH/patched/services.jar" "$MODPATH/patched/miui-services.jar" ||
  abort "Cannot set framework file security context"
ui_print "- One Magisk module; no FCM Live APK, LSPosed or Zygisk dependency"
ui_print "- Original modules were not removed or disabled by this installer"
ui_print "- Disable/remove legacy Millet Guard and FCM Live before the test reboot"
ui_print "- No model/OS allowlist; compatibility is decided by current framework capabilities"
ui_print "- Changed ROM/files and incomplete previous boot keep old generated patches off; reinstall to re-detect"
