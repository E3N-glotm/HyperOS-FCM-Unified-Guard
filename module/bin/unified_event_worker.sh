#!/system/bin/sh
MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
. "$MODDIR/bin/runtime_workers.sh"
FIFO=$RUNDIR/events.$$.fifo
reader=
retry_sleep=
alarm_guard=
cleanup_events() {
  [ -z "$reader" ] || kill "$reader" 2>/dev/null || true
  [ -z "$retry_sleep" ] || kill "$retry_sleep" 2>/dev/null || true
  [ -z "$alarm_guard" ] || kill "$alarm_guard" 2>/dev/null || true
  rm -f "$FIFO"
}
trap 'cleanup_events; exit 0' HUP INT TERM
trap cleanup_events EXIT
# HyperOS 3 and OEM-shipped logcat builds may omit --regex even when
# tag-based filtering is supported. Exiting here used to leave a stale
# events.pid and a permanent red CORE status. Keep the event worker alive
# using the same *two buffers and two tags* with shell-side event checks.
# No extra watcher, poll, wakelock or broad unfiltered subscription.
if logcat --help 2>&1 | grep -q -- '--regex'; then
  use_regex=1
  printf '%s\n' 'event logcat: regex + tag filtering' > "$RUNDIR/events-worker.mode"
else
  use_regex=0
  printf '%s\n' 'event logcat: tag-only compatibility fallback (OEM lacks --regex)' > "$RUNDIR/events-worker.mode"
fi
# One filtered subscription, two buffers, no dedicated wakeup or wake lock.
# A FIFO keeps dispatch in this process rather than a pipeline subshell.
mkfifo -m 600 "$FIFO" || exit 1
last_alarm=0
while [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ]; do
  if [ "$use_regex" = 1 ]; then
    logcat -b main -b events -v brief -T 1 \
      --regex='sourcePkg=com[.]google[.]android[.]gms([ ,}]|$)|stop [A-Za-z0-9._]+ due to SwipeUpClean' \
      -s whetstone.activity:I am_kill:I '*:S' > "$FIFO" 2>/dev/null &
  else
    # Logcat still filters on the device by *tag and priority*. The existing
    # case arms below reject unrelated records before doing any work.
    logcat -b main -b events -v brief -T 1 \
      -s whetstone.activity:I am_kill:I '*:S' > "$FIFO" 2>/dev/null &
  fi
  reader=$!
  # The parent owns this child and reaps it on restart/termination.
  while IFS= read -r line; do
    case "$line" in
      *am_kill*' due to SwipeUpClean'*)
        # Never pass the private event FIFO through cmd/am/dumpsys Binder FDs.
        /system/bin/sh "$MODDIR/bin/swipe_unstop_worker.sh" --handle-line "$line" </dev/null >/dev/null 2>&1 || true
        ;;
      *whetstone.activity*'sourcePkg=com.google.android.gms'*)
        # Alarm bursts can contain multiple delivery records for one wakeup.
        # Coalesce only within this stream; the 120s fallback stays unchanged.
        read -r event_uptime unused < /proc/uptime
        event_now=${event_uptime%%.*}
        [ $((event_now-last_alarm)) -ge 15 ] || continue
        last_alarm=$event_now
        grep -Fxq 'com.google.android.gms' "$RUNDIR/packages.list" 2>/dev/null || continue
        # Recovery may take seconds. Do not block SwipeUpClean dispatch.
        if [ -n "$alarm_guard" ]; then
          kill -0 "$alarm_guard" 2>/dev/null && continue
          wait "$alarm_guard" 2>/dev/null || true
        fi
        /system/bin/sh "$MODDIR/bin/fcm_guard.sh" alarm-event </dev/null >/dev/null 2>&1 &
        alarm_guard=$!
        ;;
    esac
  done < "$FIFO"
  wait "$reader" 2>/dev/null || true
  reader=
  sleep 5 &
  retry_sleep=$!
  wait "$retry_sleep" 2>/dev/null || true
  retry_sleep=
done
