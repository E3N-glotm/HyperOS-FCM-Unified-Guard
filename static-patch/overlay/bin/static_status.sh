#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/profile.conf"
hash_file() { sha256sum "$1" | cut -d ' ' -f 1; }
[ -r "$MODDIR/static-status.txt" ] && cat "$MODDIR/static-status.txt"
[ "$(hash_file /system/framework/services.jar)" = "$PATCHED_SERVICES_SHA256" ] &&
[ "$(hash_file /system_ext/framework/miui-services.jar)" = "$PATCHED_MIUI_SHA256" ] || {
  echo "INACTIVE: generated framework files are not mounted"
  exit 1
}
echo "STATIC_FILES_OK: services + miui-services; no LSPosed/APK bridge required"

