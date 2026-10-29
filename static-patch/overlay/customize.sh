#!/system/bin/sh
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
. "$MODPATH/bin/static_common.sh"
mkdir -p "$RUNDIR" "$MODPATH/backend" || abort "Cannot write module/configuration files"
chmod 700 "$RUNDIR"
stamp=$(date +%Y%m%d_%H%M%S)
mkdir -p "$RUNDIR/backups/adaptive-$stamp"
for f in packages.list managed.last unified.conf; do
  [ ! -f "$RUNDIR/$f" ] || cp -p "$RUNDIR/$f" "$RUNDIR/backups/adaptive-$stamp/$f"
done
if [ ! -f "$RUNDIR/packages.list" ]; then
  if [ -f /data/adb/millet_guard/packages.list ]; then cp -p /data/adb/millet_guard/packages.list "$RUNDIR/packages.list"
  else printf '%s\n' com.google.android.gms > "$RUNDIR/packages.list"; fi
fi
conf=$RUNDIR/unified.conf
[ -f "$conf" ] || printf '%s\n' DEVICEIDLE_GMS_POLICY=enforce > "$conf"
chmod 600 "$conf" "$RUNDIR/packages.list"
# Cache migration is best effort. It never blocks installation or changes the
# currently running module. Legacy verified policy can survive this upgrade.
OLD=/data/adb/modules/fcm_unified_guard
if [ "$OLD" != "$MODPATH" ] && [ -d "$OLD/backend" ]; then
  cp -a "$OLD/backend/." "$MODPATH/backend/" 2>/dev/null || true
  rm -rf "$MODPATH/backend/build.lock" "$MODPATH/backend"/.build.*
fi
if [ ! -f "$MODPATH/backend/current" ] && [ -r "$OLD/profile.conf" ] && [ -r "$OLD/patched/services.jar" ]; then
  (
    . "$OLD/profile.conf"
    SOURCE_SERVICES_PATH=${SOURCE_SERVICES_PATH:-/system/framework/services.jar}
    SOURCE_MIUI_PATH=${SOURCE_MIUI_PATH:-/system_ext/framework/miui-services.jar}
    [ "$(hash_file "$OLD/tools/policy.dex")" = "$(hash_file "$MODPATH/tools/policy.dex")" ] || exit 0
    [ "$(hash_file "$OLD/patched/services.jar")" = "${PATCHED_SERVICES_SHA256:-}" ] || exit 0
    [ "$(hash_file "$OLD/patched/miui-services.jar")" = "${PATCHED_MIUI_SHA256:-}" ] || exit 0
    valid_hash "${SOURCE_SERVICES_SHA256:-}" && valid_hash "${SOURCE_MIUI_SHA256:-}" || exit 0
    framework_path_ok "$SOURCE_SERVICES_PATH" && framework_path_ok "$SOURCE_MIUI_PATH" || exit 0
    slot=legacy-$(date +%s)
    mkdir -p "$MODPATH/backend/$slot/patched"
    cp -p "$OLD/patched/"*.jar "$MODPATH/backend/$slot/patched/" || exit 0
    {
      echo PROFILE_FORMAT=3
      echo "SOURCE_SERVICES_PATH=$SOURCE_SERVICES_PATH"
      echo "SOURCE_MIUI_PATH=$SOURCE_MIUI_PATH"
      echo "SOURCE_SERVICES_SHA256=$SOURCE_SERVICES_SHA256"
      echo "SOURCE_MIUI_SHA256=$SOURCE_MIUI_SHA256"
      echo "PATCHED_SERVICES_SHA256=$PATCHED_SERVICES_SHA256"
      echo "PATCHED_MIUI_SHA256=$PATCHED_MIUI_SHA256"
      echo "POLICY_SHA256=$(hash_file "$MODPATH/tools/policy.dex")"
      echo "BASE_API_SHA256=$(hash_file /system/framework/framework.jar)"
    } > "$MODPATH/backend/$slot/profile.conf"
    for key in ams.broadcast greeze.allow greeze.defer greeze.limit domestic.defer broadcast.autostart lists.constructor lists.whitelist network.constructor process.whitelist; do
      printf '%s\tready\tretained from verified legacy static backend\n' "$key"
    done > "$MODPATH/backend/$slot/capabilities.tsv"
    printf '%s\n' "$slot" > "$MODPATH/backend/current"
  ) || true
fi
printf '%s\t%s\n' DETECT 'Installed; automatic capability detection after Android starts; base core available' > "$MODPATH/backend/state"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH/"*.sh "$MODPATH/bin/"*.sh "$MODPATH/bin/milletctl"; do
  [ ! -f "$f" ] || set_perm "$f" 0 0 0755
done
if [ -d "$MODPATH/backend" ]; then
  find "$MODPATH/backend" -path '*/patched/*.jar' -exec chcon u:object_r:system_file:s0 {} \; 2>/dev/null || true
fi
ui_print "- Installed. Unsupported interfaces degrade individual features, not the whole module."
ui_print "- Magisk indicators: green=runtime checks OK; yellow=limited/adapting/reboot pending; red=observed error."
ui_print "- OTA automatically re-detects and rebuilds. No manual ZIP reinstall or automatic reboot."
ui_print "- User controls disabling/uninstalling this module."
