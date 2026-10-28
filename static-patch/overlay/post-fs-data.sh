#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/bin/static_common.sh"
STATUS="$MODDIR/static-status.txt"
PENDING="$MODDIR/static-boot-pending"
fail() {
  printf '%s\n' "INACTIVE: $*" > "$STATUS"
  touch "$MODDIR/disable"
  rm -f "$PENDING"
  exit 0
}
[ -r "$MODDIR/profile.conf" ] || fail "installation profile missing"
. "$MODDIR/profile.conf"
profile_valid || fail "installation profile invalid; reinstall for capability detection"
[ ! -e "$PENDING" ] || fail "previous boot was not acknowledged; automatic rollback"
if [ -d /data/adb/modules/gms_millet_guard ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/disable ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/remove ]; then
  fail "legacy Millet Guard is enabled"
fi
[ "$(current_rom_identity)" = "$INSTALLED_ROM_SHA256" ] || fail "ROM identity changed since installation; re-detect before use"
[ "$(hash_file "$SOURCE_SERVICES_PATH")" = "$SOURCE_SERVICES_SHA256" ] || fail "source services hash changed"
[ "$(hash_file "$SOURCE_MIUI_PATH")" = "$SOURCE_MIUI_SHA256" ] || fail "source OEM framework hash changed"
[ "$(hash_file "$MODDIR/patched/services.jar")" = "$PATCHED_SERVICES_SHA256" ] || fail "corrupt generated services"
[ "$(hash_file "$MODDIR/patched/miui-services.jar")" = "$PATCHED_MIUI_SHA256" ] || fail "corrupt generated miui-services"
: > "$PENDING"
mount -o bind "$MODDIR/patched/services.jar" "$SOURCE_SERVICES_PATH" ||
  fail "services bind failed"
if ! mount -o bind "$MODDIR/patched/miui-services.jar" "$SOURCE_MIUI_PATH"; then
  umount "$SOURCE_SERVICES_PATH"
  fail "miui-services bind failed; first mount reverted"
fi
printf '%s\n' "MOUNTED: static policy; awaiting Android boot completion" > "$STATUS"
