#!/system/bin/sh
MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
CONFIG=$RUNDIR/packages.list
LOG=$RUNDIR/module.log

log_msg() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

handle_line() {
  line=$1
  pkg=$(printf '%s\n' "$line" | sed -n 's/.*stop \([^ ,]*\) due to SwipeUpClean.*/\1/p')
  [ -n "$pkg" ] || return 0
  grep -Fxq "$pkg" "$CONFIG" 2>/dev/null || return 0

  state=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 'User 0:' || true)
  case "$state" in *'stopped=true'*) ;; *) return 0 ;; esac

  # Android 16 exposes a package-manager unstop command. This clears only the
  # stopped bit. It does not relaunch the process, recreate a task, or undo a
  # user-initiated Force stop whose ActivityManager reason is not SwipeUpClean.
  if cmd package unstop --user 0 "$pkg" >/dev/null 2>&1; then
    after=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 'User 0:' || true)
    case "$after" in
      *'stopped=false'*)
        log_msg "SwipeUpClean guard: cleared package stopped flag for $pkg (process remains dead; FCM may wake it)"
        ;;
      *)
        log_msg "SwipeUpClean guard: unstop command returned success but stopped flag remains for $pkg"
        ;;
    esac
  else
    log_msg "SwipeUpClean guard: failed to clear stopped flag for $pkg"
  fi
}

if [ "$1" = "--handle-line" ]; then
  shift
  handle_line "$*"
  exit 0
fi

logcat --help 2>&1 | grep -q -- '--regex' || exit 0
while true; do
  logcat -b events -v brief -T 1 \
    --regex='stop [A-Za-z0-9._]+ due to SwipeUpClean' \
    -s am_kill:I '*:S' 2>/dev/null \
  | while IFS= read -r line; do
      handle_line "$line"
    done
  sleep 3
done
