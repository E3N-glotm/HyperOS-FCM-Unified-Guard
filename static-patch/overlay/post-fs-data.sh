#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/bin/static_common.sh"
mkdir -p "$MODDIR/backend"
# An incomplete prior boot quarantines only that generated backend, never the
# module or its base workers. A changed system/policy can build a new backend.
if [ -r "$MODDIR/backend/pending" ]; then
  cp "$MODDIR/backend/pending" "$MODDIR/backend/quarantine"
  rm -f "$MODDIR/backend/pending"
  backend_note QUARANTINED "previous framework boot was not acknowledged; base core remains enabled"
fi
cache_load || { backend_note DETECT "no usable cached backend; automatic detection after boot"; exit 0; }
if [ "$(cat "$MODDIR/backend/quarantine" 2>/dev/null)" = "$generation" ]; then
  backend_note QUARANTINED "cached generation is quarantined; base core remains enabled"
  exit 0
fi
cache_payload_ok || { backend_note REBUILD "cached files damaged; automatic regeneration after boot"; exit 0; }
cache_security_ok || { backend_note REBUILD "cached framework security context unavailable; base core starts independently"; exit 0; }
cache_source_ok || { backend_note REBUILD "system inputs changed; automatic regeneration after boot"; exit 0; }
printf '%s\n' "$generation" > "$MODDIR/backend/pending"
if ! mount -o bind "$CACHE_DIR/patched/services.jar" "$SOURCE_SERVICES_PATH"; then
  rm -f "$MODDIR/backend/pending"
  backend_note ERROR "services mount failed; base core remains enabled"
  exit 0
fi
if [ -n "$SOURCE_MIUI_PATH" ] && ! mount -o bind "$CACHE_DIR/patched/miui-services.jar" "$SOURCE_MIUI_PATH"; then
  if umount "$SOURCE_SERVICES_PATH"; then
    backend_note ERROR "OEM mount failed; first mount reverted; base core remains enabled"
  else
    backend_note ERROR "OEM mount and first-mount rollback failed; framework activation incomplete"
  fi
  rm -f "$MODDIR/backend/pending"
  exit 0
fi
printf '%s %s\n' "$(boot_id)" "$generation" > "$MODDIR/backend/mounted"
backend_note ACTIVE "verified cached framework loaded; base core starts independently"
