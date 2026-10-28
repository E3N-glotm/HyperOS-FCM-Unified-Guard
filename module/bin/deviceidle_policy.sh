#!/system/bin/sh
# Native Android substitute for a *subset* of FCM Live's GMS exemptions.
# Not an Xposed broadcast hook: cannot intercept BroadcastQueue/Greeze checks.
set -u
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
CONF="$RUNDIR/unified.conf"
OWNED="$RUNDIR/deviceidle-owned.list"
PKG=com.google.android.gms
MODE=observe
[ -r "$CONF" ] && . "$CONF"
case "${DEVICEIDLE_GMS_POLICY:-observe}" in
  observe|enforce) MODE=${DEVICEIDLE_GMS_POLICY:-observe} ;;
  *) MODE=observe ;;
esac

deviceidle_list() {
  cmd deviceidle whitelist 2>/dev/null
}

is_exempt() {
  printf '%s\n' "$1" | grep -Eq "^[^,]+,$PKG,[0-9]+$"
}

case "${1:-status}" in
  status|apply)
    entries=$(deviceidle_list) || {
      echo 'DeviceIdle: unsupported; no changes made'
      exit 0
    }
    if is_exempt "$entries"; then
      echo "DeviceIdle: $PKG already exempt (mode=$MODE; owned=$([ -f "$OWNED" ] && echo yes || echo no))"
      exit 0
    fi
    if [ "${1:-status}" = status ] || [ "$MODE" != enforce ]; then
      echo "DeviceIdle: $PKG not exempt (mode=$MODE; no changes made)"
      exit 0
    fi
    # Only GMS, explicitly opted-in, with a readable native API.
    if cmd deviceidle whitelist "+$PKG" >/dev/null 2>&1 &&
       is_exempt "$(deviceidle_list)"; then
      mkdir -p "$RUNDIR" || exit 1
      printf '%s\n' "$PKG" > "$OWNED"
      chmod 0600 "$OWNED"
      echo 'DeviceIdle: GMS exemption installed by Unified Guard'
    else
      echo 'DeviceIdle: native exemption request failed'
      exit 1
    fi
    ;;
  restore)
    # Never remove a built-in/user/system exemption that predated this module.
    [ -r "$OWNED" ] || exit 0
    [ "$(cat "$OWNED" 2>/dev/null)" = "$PKG" ] || exit 1
    cmd deviceidle whitelist "-$PKG" >/dev/null 2>&1 || exit 1
    rm -f "$OWNED"
    ;;
  *)
    echo 'Usage: deviceidle_policy.sh status|apply|restore'
    exit 2
    ;;
esac
