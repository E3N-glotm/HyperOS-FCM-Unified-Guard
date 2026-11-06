#!/system/bin/sh
# Narrow, evidence-gated Box4Magisk/sing-box DNS transport repair.
# Called ONLY by the existing FCM guard after a current GMS-UID DNS failure.
# It never watches in the background, changes DNS servers, creates global
# firewall bypasses, kills GMS, or restarts an otherwise healthy proxy.
#
# The actual 2026-11-06 09:49:55 failure was:
#   mtalk.google.com: write udp 10.101.129.20:57694->223.5.5.5:53:
#   write: network is unreachable
# while no interface owned 10.101.129.20. Box's default egress had already
# changed to wlan0/another cellular IP but the old sing-box UDP source persisted.

MODDIR=${0%/*}/..
RUNDIR=/data/adb/fcm_unified_guard
BOXDIR=/data/adb/box
LOGFILE=$BOXDIR/run/sing-box.log
BOXPID=$BOXDIR/run/box.pid
SERVICE=$BOXDIR/scripts/box.service
STATE_DIR=$RUNDIR/box_dns_repair
LOCK_DIR=$STATE_DIR/lock
LAST_EPOCH=$STATE_DIR/last_restart.epoch
LAST_EVENT=$STATE_DIR/last_handled.signature
OUTLOG=$RUNDIR/module.log
MIN_RESTART_GAP=1800
MAX_LOG_AGE=900

mode=${1:-probe}
case "$mode" in probe|repair) :;; *) exit 2;; esac

# Fail closed on ROMs without Box4Magisk, when the user has disabled/stopped
# the proxy, or if the process is not the current tracked sing-box instance.
[ -f "$BOXPID" ] && [ -r "$LOGFILE" ] && [ -x "$SERVICE" ] || exit 0
[ ! -e /data/adb/modules/box_for_root/disable ] || exit 0
[ ! -e "$BOXDIR/manual" ] || exit 0
read -r proxy_pid < "$BOXPID" 2>/dev/null || exit 0
case "$proxy_pid" in ''|*[!0-9]*) exit 0;; esac
[ -r "/proc/$proxy_pid/comm" ] || exit 0
read -r proxy_name < "/proc/$proxy_pid/comm" 2>/dev/null || exit 0
[ "$proxy_name" = "sing-box" ] && kill -0 "$proxy_pid" 2>/dev/null || exit 0

# No new network test: a real resolver failure was observed by fcm_guard.
# Only the most recent 512 lines are examined, avoiding a growing log scan.
# Every successful repair consumes one exact failure signature.
find_unbound_failure() {
  failure_line=$(busybox tail -n 512 "$LOGFILE" 2>/dev/null \
    | grep -F 'dns: exchange failed for mtalk.google.com.' \
    | grep -E 'write udp [0-9.]+:[0-9]+->[0-9.]+:53: write: network is unreachable' \
    | tail -n 1)
  [ -n "$failure_line" ] || return 1

  failure_date=$(printf '%s\n' "$failure_line" | busybox awk '{print $2 " " $3}')
  failure_epoch=$(date -d "$failure_date" +%s 2>/dev/null) || return 1
  now_epoch=$(date +%s)
  case "$failure_epoch:$now_epoch" in *[!0-9:]*|:*|*:) return 1;; esac
  failure_age=$((now_epoch-failure_epoch))
  [ "$failure_age" -ge 0 ] && [ "$failure_age" -le "$MAX_LOG_AGE" ] || return 1

  old_source=$(printf '%s\n' "$failure_line" \
    | busybox sed -n 's/.*write udp \([0-9][0-9.]*\):[0-9][0-9]*->[0-9][0-9.]*:53: write: network is unreachable.*/\1/p')
  [ -n "$old_source" ] || return 1
  # Disallow metacharacters, hostnames, IPv6 and malformed addresses.
  printf '%s\n' "$old_source" | busybox awk -F '.' '
    NF!=4 {exit 1}
    {for(i=1;i<=4;i++)
       if ($i !~ /^[0-9]{1,3}$/ || $i+0>255) exit 1}
  ' || return 1

  # A source address that is still assigned is NOT evidence of stale binding:
  # the error could be upstream connectivity or ordinary network loss.
  if ip -4 -o addr show scope global up 2>/dev/null \
    | busybox awk -v address="$old_source" \
      '{split($4,p,"/"); if(p[1]==address) found=1}
       END{exit found?0:1}'; then
    return 1
  fi

  # Require a currently routable default IPv4 path. Never restart during
  # mobile data / Wi-Fi handover when no valid egress has been established.
  ip -4 route get 223.5.5.5 >/dev/null 2>&1 || return 1

  failure_signature="$failure_epoch:$old_source:$proxy_pid"
  [ -n "$failure_signature" ]
}

find_unbound_failure || exit 0
if [ "$mode" = probe ]; then
  printf 'stale_singbox_fcm_dns_source=%s error_age=%ss proxy_pid=%s\n' \
    "$old_source" "$failure_age" "$proxy_pid"
  exit 0
fi

# The FCM guard owns a process-identity lock; the separate lock here prevents
# another caller racing a Box service restart. No long-lived worker is added.
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
mkdir "$LOCK_DIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM
find_unbound_failure || exit 0
last_event=$(cat "$LAST_EVENT" 2>/dev/null)
[ "$last_event" != "$failure_signature" ] || exit 0
last_restart=$(cat "$LAST_EPOCH" 2>/dev/null)
case "$last_restart" in ''|*[!0-9]*) last_restart=0;; esac
[ $((now_epoch-last_restart)) -ge "$MIN_RESTART_GAP" ] || exit 0

# Consume evidence BEFORE the restart. Even on failure, never retry the same
# error in a busy loop. A newer independently logged stale source may retry
# after the thirty-minute floor on an existing guard wake.
printf '%s\n' "$failure_signature" > "$LAST_EVENT"
printf '%s\n' "$now_epoch" > "$LAST_EPOCH"
printf '%s FCM guard: verified stale sing-box DNS UDP source=%s age=%ss; one controlled Box recovery (30m floor)\n' \
  "$(date '+%F %T')" "$old_source" "$failure_age" >> "$OUTLOG"

# Use Box's own lifecycle manager to keep its route/iptables setup coherent.
# It may briefly interrupt proxied traffic but will not touch GMS process.
busybox timeout 75 /system/bin/sh "$SERVICE" restart >/dev/null 2>&1
rc=$?
printf '%s FCM guard: controlled Box DNS recovery rc=%s; rechecking GMS DNS on next normal poll\n' \
  "$(date '+%F %T')" "$rc" >> "$OUTLOG"
[ "$rc" -eq 0 ] || exit 1
printf 'BOX_FCM_DNS_RECOVERY_TRIGGERED\n'
