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
cleanup_settings() {
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
        # One SettingsProvider update produces multiple create/write/move
        # events. Coalesce within 5s; the 300s safety sweep is unchanged.
        read -r boot_time unused < /proc/uptime
        now=${boot_time%%.*}
        [ "$now" -ge "$((last_reconcile+5))" ] || continue
        last_reconcile=$now
        # cmd forwards stdin over Binder. system_server cannot read our
        # adb_data_file FIFO under SELinux; give child commands /dev/null.
        /system/bin/sh "$MODDIR/bin/reconcile.sh" "inotify:$events:$sub" </dev/null >/dev/null 2>&1 || true;;
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
