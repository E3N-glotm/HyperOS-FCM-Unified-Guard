#!/system/bin/sh
# Preserve both modules and return to the pre-v0.2 live-core selection.
set -eu
NEW=/data/adb/modules/fcm_unified_guard
OLD=/data/adb/modules/gms_millet_guard
RUN=/data/adb/fcm_unified_guard
touch "$NEW/disable"
[ ! -d /data/adb/modules_update/fcm_unified_guard ] || touch /data/adb/modules_update/fcm_unified_guard/disable
sh "$NEW/bin/runtime_workers.sh" stop
# No uninstall: existing settings and the E3N bridge remain available.
rm -f "$OLD/disable"
nohup sh "$OLD/service.sh" > "$RUN/rollback-start.log" 2>&1 < /dev/null &
echo 'Original core restarted; verify its workers and GMS connection.'
