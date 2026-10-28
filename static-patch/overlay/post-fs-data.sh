#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/profile.conf"
STATUS="$MODDIR/static-status.txt"
PENDING="$MODDIR/static-boot-pending"
fail() {
  printf '%s\n' "INACTIVE: $*" > "$STATUS"
  touch "$MODDIR/disable"
  rm -f "$PENDING"
  exit 0
}
hash_file() { sha256sum "$1" | cut -d ' ' -f 1; }
[ ! -e "$PENDING" ] || fail "previous boot was not acknowledged; automatic rollback"
if [ -d /data/adb/modules/gms_millet_guard ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/disable ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/remove ]; then
  fail "legacy Millet Guard is enabled"
fi
[ "$(getprop ro.product.device)" = "$TARGET_DEVICE" ] || fail "device changed"
[ "$(getprop ro.build.version.sdk)" = "$TARGET_SDK" ] || fail "SDK changed"
[ "$(getprop ro.build.version.incremental)" = "$TARGET_BUILD" ] || fail "ROM updated; rebuild required"
[ "$(hash_file /system/framework/services.jar)" = "$SOURCE_SERVICES_SHA256" ] || fail "stock services hash changed"
[ "$(hash_file /system_ext/framework/miui-services.jar)" = "$SOURCE_MIUI_SHA256" ] || fail "stock miui-services hash changed"
[ "$(hash_file "$MODDIR/patched/services.jar")" = "$PATCHED_SERVICES_SHA256" ] || fail "corrupt generated services"
[ "$(hash_file "$MODDIR/patched/miui-services.jar")" = "$PATCHED_MIUI_SHA256" ] || fail "corrupt generated miui-services"
: > "$PENDING"
mount -o bind "$MODDIR/patched/services.jar" /system/framework/services.jar ||
  fail "services bind failed"
if ! mount -o bind "$MODDIR/patched/miui-services.jar" /system_ext/framework/miui-services.jar; then
  umount /system/framework/services.jar
  fail "miui-services bind failed; first mount reverted"
fi
printf '%s\n' "MOUNTED: static policy; awaiting Android boot completion" > "$STATUS"

