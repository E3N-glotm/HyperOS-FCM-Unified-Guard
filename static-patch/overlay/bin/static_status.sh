#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/bin/static_common.sh"
[ -r "$MODDIR/profile.conf" ] || { echo 'INACTIVE: installation profile missing'; exit 1; }
. "$MODDIR/profile.conf"
profile_valid || { echo 'INACTIVE: installation profile invalid'; exit 1; }
[ -r "$MODDIR/static-status.txt" ] && cat "$MODDIR/static-status.txt"
[ "$(hash_file "$SOURCE_SERVICES_PATH")" = "$PATCHED_SERVICES_SHA256" ] &&
[ "$(hash_file "$SOURCE_MIUI_PATH")" = "$PATCHED_MIUI_SHA256" ] || {
  echo "INACTIVE: generated framework files are not mounted"
  exit 1
}
echo "STATIC_FILES_OK: services + miui-services; no LSPosed/APK bridge required"
