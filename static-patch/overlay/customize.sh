#!/system/bin/sh
# A static ROM patch is generated locally; no Xiaomi framework is distributed.
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
. "$MODPATH/profile.conf"
hash_file() { sha256sum "$1" | cut -d ' ' -f 1; }
[ "$(getprop ro.product.device)" = "$TARGET_DEVICE" ] || abort "Unsupported device"
[ "$(getprop ro.build.version.sdk)" = "$TARGET_SDK" ] || abort "Unsupported Android API"
[ "$(getprop ro.build.version.incremental)" = "$TARGET_BUILD" ] || abort "Unsupported ROM build; refusing an unverified patch"
[ "$(hash_file /system/framework/services.jar)" = "$SOURCE_SERVICES_SHA256" ] || abort "services.jar differs from verified stock"
[ "$(hash_file /system_ext/framework/miui-services.jar)" = "$SOURCE_MIUI_SHA256" ] || abort "miui-services.jar differs from verified stock"
ui_print "- Generating FCM-only framework policy in staging (may take several minutes)"
mkdir -p "$MODPATH/.staging"
CLASSPATH="$MODPATH/tools/patcher.jar" /apex/com.android.art/bin/dalvikvm64 -Xmx1024m \
  io.github.e3n.fcmu.Patcher /system/framework/services.jar /system_ext/framework/miui-services.jar \
  "$MODPATH/tools/policy.dex" "$MODPATH/.staging" > "$MODPATH/install-report.txt" 2>&1 ||
  abort "Patch generation rejected; inspect install-report.txt"
ui_print "- Verifying DEX alignment and ART class loading"
CLASSPATH="$MODPATH/tools/verify.jar" /apex/com.android.art/bin/dalvikvm64 \
  io.github.e3n.fcmu.Verify --jar "$MODPATH/.staging/services.jar" "$MODPATH/.staging/miui-services.jar" \
  >> "$MODPATH/install-report.txt" 2>&1 || abort "Generated JAR failed ZIP verification"
CLASSPATH="$MODPATH/tools/verify.jar:$MODPATH/.staging/services.jar:$MODPATH/.staging/miui-services.jar:$SYSTEMSERVERCLASSPATH" \
  /apex/com.android.art/bin/dalvikvm64 -Xmx512m -Xverify:all io.github.e3n.fcmu.Verify \
  io.github.e3n.fcmu.StaticPolicy com.android.server.am.ActivityManagerService \
  com.android.server.am.BroadcastQueueModernStubImpl com.android.server.am.ProcessPolicy \
  com.miui.server.greeze.GreezeManagerService com.miui.server.greeze.DomesticPolicyManager \
  com.miui.server.greeze.power.ListAppsManager com.miui.server.greeze.power.AwareResourceControl \
  >> "$MODPATH/install-report.txt" 2>&1 || abort "ART rejected the generated policy"
mv "$MODPATH/.staging" "$MODPATH/patched"
{
  echo "PATCHED_SERVICES_SHA256=$(hash_file "$MODPATH/patched/services.jar")"
  echo "PATCHED_MIUI_SHA256=$(hash_file "$MODPATH/patched/miui-services.jar")"
} >> "$MODPATH/profile.conf"
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
ui_print "- ROM/hash mismatch and incomplete previous boot cause the static backend to stay off"
