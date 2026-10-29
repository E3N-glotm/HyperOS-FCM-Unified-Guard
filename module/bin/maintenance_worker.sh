#!/system/bin/sh
MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
SLEEP_PID=
trap '[ -z "$SLEEP_PID" ] || kill "$SLEEP_PID" 2>/dev/null; exit 0' HUP INT TERM
uptime_seconds() {
  read -r uptime_value unused < /proc/uptime
  printf '%s\n' "${uptime_value%%.*}"
}
now=$(uptime_seconds)
next_fcm=$((now+120))
next_policy=$((now+300))
while [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ]; do
  now=$(uptime_seconds)
  if [ "$now" -ge "$next_policy" ]; then
    /system/bin/sh "$MODDIR/bin/reconcile.sh" safety
    [ ! -f "$MODDIR/bin/health_status.sh" ] || /system/bin/sh "$MODDIR/bin/health_status.sh" --cached </dev/null >/dev/null 2>&1
    next_policy=$(( $(uptime_seconds)+300 ))
  fi
  if [ "$now" -ge "$next_fcm" ]; then
    if grep -Fxq 'com.google.android.gms' "$RUNDIR/packages.list" 2>/dev/null; then
      /system/bin/sh "$MODDIR/bin/fcm_guard.sh" poll
    fi
    next_fcm=$(( $(uptime_seconds)+120 ))
  fi
  now=$(uptime_seconds)
  deadline=$next_fcm
  [ "$next_policy" -ge "$deadline" ] || deadline=$next_policy
  delay=$((deadline-now))
  [ "$delay" -gt 0 ] || delay=1
  sleep "$delay" &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || true
  SLEEP_PID=
done
