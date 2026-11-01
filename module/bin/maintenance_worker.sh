#!/system/bin/sh
MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
WAKE_BIN=$MODDIR/bin/fcmu_alarm_wait
WAKE_STATUS=$RUNDIR/alarm-wakeup.state
WAKE_ERROR_LOGGED=0
SLEEP_PID=
trap '[ -z "$SLEEP_PID" ] || kill "$SLEEP_PID" 2>/dev/null; exit 0' HUP INT TERM
uptime_seconds() {
  read -r uptime_value unused < /proc/uptime
  printf '%s\n' "${uptime_value%%.*}"
}
# Linux CLOCK_BOOTTIME_ALARM uses the kernel alarmtimer, capable of waking
# a suspended CPU. A userspace sleep(120) is only a fallback, not a wakeup.
# One alarm at a time; no CPU busy loop or held wakelock.
wait_for_deadline() {
  delay=$1
  if [ -x "$WAKE_BIN" ]; then
    "$WAKE_BIN" "$delay" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null
    rc=$?
    SLEEP_PID=
    if [ "$rc" -eq 0 ]; then
      printf 'kernel-alarmtimer epoch=%s interval=%s\n' "$(date +%s)" "$delay" > "$WAKE_STATUS"
      return 0
    fi
  else
    rc=127
  fi
  if [ "$WAKE_ERROR_LOGGED" -eq 0 ]; then
    printf '%s FCM alarmtimer unavailable rc=%s; degraded to non-wakeup sleep\n' "$(date '+%F %T')" "$rc" >> "$RUNDIR/module.log"
    WAKE_ERROR_LOGGED=1
  fi
  printf 'fallback-sleep epoch=%s rc=%s\n' "$(date +%s)" "$rc" > "$WAKE_STATUS"
  sleep "$delay" &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || true
  SLEEP_PID=
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
    # Healthy state keeps the existing low-cost two-minute check. Once an
    # outage has been observed, retry at 30-second intervals on existing
    # process wakes. This does not request a new wakelock or wakeup alarm.
    if [ -f "$RUNDIR/fcm_down_since.epoch" ]; then
      next_fcm=$(( $(uptime_seconds)+30 ))
    else
      next_fcm=$(( $(uptime_seconds)+120 ))
    fi
  fi
  now=$(uptime_seconds)
  deadline=$next_fcm
  [ "$next_policy" -ge "$deadline" ] || deadline=$next_policy
  delay=$((deadline-now))
  [ "$delay" -gt 0 ] || delay=1
  wait_for_deadline "$delay"
done
