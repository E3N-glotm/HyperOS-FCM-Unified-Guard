#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/bin/static_common.sh"
cat "$MODDIR/backend/state" 2>/dev/null || true
if cache_load && cache_payload_ok && cache_security_ok && cache_mounted; then
  echo 'STATIC_FILES_OK: adapted cache mounted; consult per-feature runtime health'
  exit 0
fi
echo 'STATIC_NOT_LOADED: base guard remains independent; adaptation/status available in Magisk Action'
exit 1
