#!/system/bin/sh
# PID + proc start time + module path, never kill an unverified reused PID.
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
MODULE_ROOT=${FCM_UNIFIED_MODULE:-/data/adb/modules/fcm_unified_guard}
worker_ticks() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  IFS= read -r worker_stat < "/proc/$1/stat" 2>/dev/null || return 1
  worker_tail=${worker_stat##*) }
  [ "$worker_tail" != "$worker_stat" ] || return 1
  set -- $worker_tail
  [ "$#" -ge 20 ] || return 1
  shift 19
  printf '%s\n' "$1"
}
record_worker() {
  worker_start=$(worker_ticks "$2") || return 1
  printf '%s %s\n' "$2" "$worker_start" > "$RUNDIR/$1.pid"
}
stop_workers() {
  for worker_name in settings maintenance events inotifyd safety fcm fcm_event swipe_unstop; do
    worker_file=$RUNDIR/$worker_name.pid
    [ -f "$worker_file" ] || continue
    read -r worker_pid worker_start < "$worker_file" || continue
    case "$worker_pid" in ''|*[!0-9]*) continue;; esac
    # Only v0.2+ records have identity metadata. Legacy workers require the
    # explicit migration procedure; never guess from a bare, stale PID file.
    case "$worker_start" in ''|*[!0-9]*) continue;; esac
    [ "$(worker_ticks "$worker_pid")" = "$worker_start" ] || continue
    kill "$worker_pid" 2>/dev/null || true
    rm -f "$worker_file"
  done
}
case "${1:-}" in stop) stop_workers;; esac
