#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/bin/static_common.sh"
# No static-backend gate: the guard starts on every supported Magisk install.
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
/system/bin/sh "$MODDIR/core-service.sh" </dev/null
i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 180 ]; do sleep 2; i=$((i+1)); done
[ "$(getprop sys.boot_completed)" = 1 ] || exit 0
sleep 20
if cache_load && cache_payload_ok && cache_mounted; then
  rm -f "$MODDIR/backend/pending"
  backend_note ACTIVE "framework cache loaded; delivery still needs real-message observation"
fi
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null >/dev/null 2>&1 || true
# Heavy adaptation happens once after Android has started, never inside Magisk's
# time-limited post-fs-data phase. No reboot is issued by any module script.
/system/bin/sh "$MODDIR/bin/build_backend.sh" auto </dev/null >/dev/null 2>&1
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null >/dev/null 2>&1 || true
