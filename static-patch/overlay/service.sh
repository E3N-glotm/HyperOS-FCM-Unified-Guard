#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/bin/static_common.sh"
# No static-backend gate: the guard starts on every supported Magisk install.
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
backend_read_state
[ "$phase" != CHECKING ] || backend_note CHECKING "checking this boot before starting the base guard"
/system/bin/sh "$MODDIR/core-service.sh" </dev/null
i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 180 ]; do sleep 2; i=$((i+1)); done
[ "$(getprop sys.boot_completed)" = 1 ] || exit 0
sleep 20
# Acknowledge the actual completed boot independently of static framework
# adaptation. Do not change the native quarantine state on failure.
if [ -f "$MODDIR/zygisk/arm64-v8a.so" ]; then
  current_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  recorded_boot=$(cat "$MODDIR/backend/pk-boot.pending" 2>/dev/null)
  if [ -n "$current_boot" ] && [ "$current_boot" = "$recorded_boot" ]; then
    rm -f "$MODDIR/backend/pk-boot.pending"
    printf '%s\n' "boot completed; PowerKeeper Zygisk startup acknowledged" > "$MODDIR/backend/pk-boot.status"
  fi
  # Update target package list and read-only method reports ONCE per boot.
  # This prepares the next boot; it never restarts PowerKeeper or GMS.
  /system/bin/sh "$MODDIR/bin/powerkeeper_processes.sh" </dev/null >/dev/null 2>&1 || true
  /system/bin/sh "$MODDIR/bin/powerkeeper_probe.sh" </dev/null >"$MODDIR/backend/powerkeeper-probe-last.txt" 2>&1 || true
fi
if cache_load && cache_payload_ok && cache_mounted; then
  rm -f "$MODDIR/backend/pending"
  backend_note ACTIVE "framework cache loaded; delivery still needs real-message observation"
fi
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null >/dev/null 2>&1 || true
# Heavy adaptation happens once after Android has started, never inside Magisk's
# time-limited post-fs-data phase. No reboot is issued by any module script.
/system/bin/sh "$MODDIR/bin/build_backend.sh" auto </dev/null >/dev/null 2>&1
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null >/dev/null 2>&1 || true
