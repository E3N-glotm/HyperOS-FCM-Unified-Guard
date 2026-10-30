#!/system/bin/sh
MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=/system/xbin/busybox
[ -x "$BB" ] || BB=busybox
FIFO=$RUNDIR/settings.$$.fifo
watcher=
retry_sleep=
last_reconcile=0
deferred_reconcile=
cleanup_settings() {
  # One trailing-edge reconcile is allowed per Settings event burst.
  [ -z "$deferred_reconcile" ] || kill "$deferred_reconcile" 2>/dev/null || true
  [ -z "$watcher" ] || kill "$watcher" 2>/dev/null || true
  [ -z "$retry_sleep" ] || kill "$retry_sleep" 2>/dev/null || true
  rm -f "$FIFO"
}
trap 'cleanup_settings; exit 0' HUP INT TERM
trap cleanup_settings EXIT
mkfifo -m 600 "$FIFO" || exit 1
while [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ]; do
  # '-' streams events instead of execing one handler for EVERY directory
  # event (including irrelevant secure settings). Filtering is shell builtin.
  "$BB" inotifyd - /data/system/users/0:wymnDo "$RUNDIR":wymnDo > "$FIFO" 2>/dev/null &
  watcher=$!
  while read -r events watched sub; do
    case "$watched:$sub" in
      /data/system/users/0:settings_system.xml|/data/system/users/0:settings_system.xml.*|/data/system/users/0:)
        # A SettingsProvider update emits several write/rename events.
        # The former 5-second drop-only debounce could discard a real
        # PowerKeeper whitelist rewrite and leave GMS exposed for the
        # full 300-second safety interval. Process the first event now,
        # with a bounded trailing-edge pass if more arrive within 2s.
        read -r boot_time unused < /proc/uptime
        now=${boot_time%%.*}
        if [ "$now" -ge "$((last_reconcile+2))" ]; then
          last_reconcile=$now
          # 'cmd settings' passes stdin to Binder: never forward our FIFO.
          /system/bin/sh "$MODDIR/bin/reconcile.sh" "inotify:$events:$sub" </dev/null >/dev/null 2>&1 || true
        else
          if [ -n "$deferred_reconcile" ] && kill -0 "$deferred_reconcile" 2>/dev/null; then
            continue
          fi
          # Event-driven one-shot, NOT a recurring watcher or alarm.
          # Coalesces a burst and always checks the final effective value.
          (
            sleep 1
            [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ] ||
              /system/bin/sh "$MODDIR/bin/reconcile.sh" inotify-deferred </dev/null >/dev/null 2>&1 || true
          ) </dev/null >/dev/null 2>&1 &
          deferred_reconcile=$!
        fi;;
      "$RUNDIR":packages.list)
        /system/bin/sh "$MODDIR/bin/reconcile.sh" config-event </dev/null >/dev/null 2>&1 || true;;
    esac
  done < "$FIFO"
  wait "$watcher" 2>/dev/null || true
  watcher=
  sleep 5 &
  retry_sleep=$!
  wait "$retry_sleep" 2>/dev/null || true
  retry_sleep=
done
