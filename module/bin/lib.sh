#!/system/bin/sh
RUNDIR=/data/adb/fcm_unified_guard
BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=/system/xbin/busybox
[ -x "$BB" ] || BB=busybox
CONFIG=$RUNDIR/packages.list
OWNED=$RUNDIR/managed.last
LOG=$RUNDIR/module.log
mkdir -p "$RUNDIR"
valid_pkg() {
  # Conservative Android-style package syntax; must contain at least one dot.
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_]+)+$'
}
normalize_file() {
  f=$1
  [ -f "$f" ] || return 0
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$f" \
    | sed '/^$/d;/^#/d' \
    | awk '!seen[$0]++'
}
managed_list() {
  normalize_file "$CONFIG" | while IFS= read -r pkg; do
    valid_pkg "$pkg" && printf '%s\n' "$pkg"
  done
}
owned_list() {
  normalize_file "$OWNED" | while IFS= read -r pkg; do
    valid_pkg "$pkg" && printf '%s\n' "$pkg"
  done
}
setting_list() {
  cur=$(settings --user 0 get system MILLET_NO_RESTRICT_APP 2>/dev/null)
  [ "$cur" = "null" ] && cur=""
  printf '%s' "$cur" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | awk '!seen[$0]++'
}
join_csv() {
  awk 'NF { if (out!="") out=out ", "; out=out $0 } END { print out }'
}
contains_line() {
  needle=$1
  grep -Fxq "$needle"
}
run_timeout() {
  "$BB" timeout 5 "$@"
}
log_msg() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}
