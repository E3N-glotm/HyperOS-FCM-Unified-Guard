#!/system/bin/sh
MODDIR=${0%/*}
/system/bin/sh "$MODDIR/bin/static_status.sh" check || exit 0
# The original optimized core retains its PID/start-tick locks and three workers.
/system/bin/sh "$MODDIR/core-service.sh"
i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 180 ]; do
  sleep 2
  i=$((i+1))
done
[ "$(getprop sys.boot_completed)" = 1 ] || exit 0
sleep 20
/system/bin/sh "$MODDIR/bin/static_status.sh" check || exit 0
rm -f "$MODDIR/static-boot-pending"
printf '%s\n' "BOOT_OK: static framework policy + unified core; push delivery still needs observation" > "$MODDIR/static-status.txt"
