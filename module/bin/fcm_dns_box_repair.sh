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
case "$mode" in probe|repair|fallback) :;; *) exit 2;; esac

# Fail closed on ROMs without Box4Magisk, when the user has disabled/stopped
# the proxy, or if the process is not the current tracked sing-box instance.
[ -f "$BOXPID" ] && [ -r "$LOGFILE" ] && [ -x "$SERVICE" ] || exit 0
[ ! -e /data/adb/modules/box_for_root/disable ] || exit 0
[ ! -e "$BOXDIR/manual" ] || exit 0
# Box4Magisk writes box.pid as decimal bytes WITHOUT a final newline.
# POSIX read sets the variable but returns nonzero at EOF in that case, so
# 'read ... || exit' incorrectly disabled all alpha16/alpha17 recovery paths.
# Command substitution accepts the existing no-LF format; the numeric-only
# contract below still rejects empty, malformed, injected, or stale PIDs.
proxy_pid=$(cat "$BOXPID" 2>/dev/null) || exit 0
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

  # The failure must belong to this exact proxy PROCESS. If Box restarted
  # after the logged error, never restart the new healthy instance because
  # of a stale entry left over in the same log file.
  proxy_stat=
  IFS= read -r proxy_stat < "/proc/$proxy_pid/stat" 2>/dev/null || return 1
  proxy_tail=${proxy_stat##*) }
  [ "$proxy_tail" != "$proxy_stat" ] || return 1
  set -- $proxy_tail
  [ "$#" -ge 20 ] || return 1
  shift 19
  proxy_start_ticks=$1
  case "$proxy_start_ticks" in ''|*[!0-9]*) return 1;; esac
  hz=$(getconf CLK_TCK 2>/dev/null) || return 1
  case "$hz" in ''|*[!0-9]*|0) return 1;; esac
  read -r uptime_value unused < /proc/uptime || return 1
  uptime_seconds=${uptime_value%%.*}
  case "$uptime_seconds" in ''|*[!0-9]*) return 1;; esac
  proxy_started_epoch=$((now_epoch-uptime_seconds+proxy_start_ticks/hz))
  [ "$failure_epoch" -ge "$proxy_started_epoch" ] || return 1

  old_source=$(printf '%s\n' "$failure_line" \
    | busybox sed -n 's/.*write udp \([0-9][0-9.]*\):[0-9][0-9]*->[0-9][0-9.]*:53: write: network is unreachable.*/\1/p')
  [ -n "$old_source" ] || return 1
  # Disallow metacharacters, hostnames, IPv6 and malformed addresses.
  printf '%s\n' "$old_source" | busybox awk -F '.' '
    NF!=4 {exit 1}
    {for(i=1;i<=4;i++)
       if ($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255) exit 1}
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

  failure_signature="$failure_epoch:$old_source:$proxy_pid:$proxy_start_ticks"
  [ -n "$failure_signature" ]
}

# alpha17: a SECOND, independently gated recovery path for nights when the
# Android resolver fails for many minutes but sing-box did not emit the exact
# stale-source error required by alpha16. This is deliberately NOT a generic
# "restart on UNKNOWN_HOST": it requires a root-vs-GMS resolver mismatch,
# a live, mature Box process, active Box DNS capture, a valid IPv4 route and
# one attempt PER outage with at least a 6-hour global floor.
if [ "$mode" = fallback ]; then
  outage_stamp=${2:-0}
  case "$outage_stamp" in ''|*[!0-9]*) exit 0;; esac
  now_epoch=$(date +%s)
  outage_age=$((now_epoch-outage_stamp))
  [ "$outage_age" -ge 900 ] && [ "$outage_age" -le 86400 ] || exit 0
  [ -r "$RUNDIR/fcm_down_since.epoch" ] || exit 0
  read -r real_down < "$RUNDIR/fcm_down_since.epoch" || exit 0
  [ "$real_down" = "$outage_stamp" ] || exit 0

  # GMS UID, unlike root, may be subject to per-app firewall/DNS restrictions.
  gms_uid=$(cat "$RUNDIR/fcm_bypass.uid" 2>/dev/null)
  case "$gms_uid" in ''|*[!0-9]*) exit 0;; esac
  [ "$gms_uid" -ge 10000 ] || exit 0
  [ "$gms_uid" = "$(pm list packages -U com.google.android.gms 2>/dev/null \
      | busybox awk '$1=="package:com.google.android.gms" {sub(/^uid:/,"",$2);print $2;exit}')" ] || exit 0

  # Box's DNS capture must actually be present. Merely having sing-box
  # running is insufficient evidence that its DNS path is implicated.
  iptables -w 5 -t mangle -S BOX_LOCAL 2>/dev/null \
    | grep -Eq -- '^-A BOX_LOCAL .*udp .*--dport 53 .*MARK' || exit 0
  ip -4 route get 223.5.5.5 >/dev/null 2>&1 || exit 0

  # Do not disturb a newly started or recently recovered proxy.
  process_stat=
  IFS= read -r process_stat < "/proc/$proxy_pid/stat" 2>/dev/null || exit 0
  process_tail=${process_stat##*) }
  [ "$process_tail" != "$process_stat" ] || exit 0
  set -- $process_tail
  [ "$#" -ge 20 ] || exit 0
  shift 19
  process_ticks=$1
  case "$process_ticks" in ''|*[!0-9]*) exit 0;; esac
  hz=$(getconf CLK_TCK 2>/dev/null) || exit 0
  case "$hz" in ''|*[!0-9]*|0) exit 0;; esac
  read -r up_seconds unused < /proc/uptime || exit 0
  up_seconds=${up_seconds%%.*}
  case "$up_seconds" in ''|*[!0-9]*) exit 0;; esac
  process_age=$((up_seconds-process_ticks/hz))
  [ "$process_age" -ge 1200 ] || exit 0

  mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM

  last_fallback=$(cat "$STATE_DIR/fallback_last.epoch" 2>/dev/null)
  case "$last_fallback" in ''|*[!0-9]*) last_fallback=0;; esac
  [ $((now_epoch-last_fallback)) -ge 21600 ] || exit 0
  last_any=$(cat "$LAST_EPOCH" 2>/dev/null)
  case "$last_any" in ''|*[!0-9]*) last_any=0;; esac
  [ $((now_epoch-last_any)) -ge 1800 ] || exit 0
  [ "$(cat "$STATE_DIR/fallback_outage.epoch" 2>/dev/null)" != "$outage_stamp" ] || exit 0
  last_probe=$(cat "$STATE_DIR/fallback_probe.epoch" 2>/dev/null)
  case "$last_probe" in ''|*[!0-9]*) last_probe=0;; esac
  [ $((now_epoch-last_probe)) -ge 900 ] || exit 0
  printf '%s\n' "$now_epoch" > "$STATE_DIR/fallback_probe.epoch"

  # GMS's own libc resolver must STILL fail, and with an explicit DNS error.
  # Missing su/PING permission or an unreachable ICMP target is not enough.
  uid_lookup=$(busybox timeout 7 su -s /system/bin/sh "$gms_uid" \
    -c '/system/bin/ping -c 1 -W 1 mtalk.google.com' 2>&1)
  if printf '%s\n' "$uid_lookup" | grep -Eq '^PING[[:space:]].*\([0-9][0-9.]*\)'; then
    exit 0
  fi
  printf '%s\n' "$uid_lookup" | grep -Eqi 'unknown host|bad address|name or service not known|temporary failure in name resolution' || exit 0

  # alpha23: the previous 'root resolves, GMS does not' gate was wrong.
  # An ordinary root/GID0 UDP53 query is transparently marked into the Box
  # local proxy (route table 2024), while uid0/gid3005 is deliberately
  # bypassed by the verified Box owner rule. Such probes are DIFFERENT paths.
  # Only restart Box if the direct physical DNS path works while the Box
  # captured DNS path itself fails. If BOTH work but GMS libc still fails,
  # Box is not proven broken: don't disrupt other proxy users.
  iptables -w 5 -t mangle -S BOX_LOCAL 2>/dev/null |
    grep -Fq -- '-m owner --uid-owner 0 --gid-owner 3005 -j RETURN' || exit 0

  physical_dns_ok=0
  box_dns_ok=0
  for upstream in 223.5.5.5 61.139.2.69; do
    direct_answer=$(busybox timeout 8 su -g 3005 0 -c \
      "busybox timeout 6 busybox nslookup mtalk.google.com $upstream" 2>/dev/null)
    if printf '%s\n' "$direct_answer" | grep -Fq 'Name:      mtalk.google.com'; then
      physical_dns_ok=1
      break
    fi
  done
  [ "$physical_dns_ok" = 1 ] || exit 0
  for upstream in 223.5.5.5 61.139.2.69; do
    box_answer=$(busybox timeout 8 su -g 0 0 -c \
      "busybox timeout 6 busybox nslookup mtalk.google.com $upstream" 2>/dev/null)
    if printf '%s\n' "$box_answer" | grep -Fq 'Name:      mtalk.google.com'; then
      box_dns_ok=1
      break
    fi
  done
  [ "$box_dns_ok" = 0 ] || {
    printf '%s FCM guard: Android DNS failed but BOTH direct(GID3005) and Box-captured(GID0) DNS resolved; Box restart withheld; cause likely elsewhere\n' \
      "$(date '+%F %T')" >> "$OUTLOG"
    exit 0
  }

  # A single evidence-gated restart remains possible for an actually
  # broken Box DNS path, with the existing per-outage and six-hour limits.
  printf '%s FCM guard: physical direct DNS resolves but Box-captured DNS fails; one conditional Box recovery eligible, outage=%ss\n' \
    "$(date '+%F %T')" "$outage_age" >> "$OUTLOG"
  printf '%s\n' "$outage_stamp" > "$STATE_DIR/fallback_outage.epoch"
  printf '%s\n' "$now_epoch" > "$STATE_DIR/fallback_last.epoch"
  printf '%s\n' "$now_epoch" > "$LAST_EPOCH"

  busybox timeout 75 /system/bin/sh "$SERVICE" restart >/dev/null 2>&1
  rc=$?
  printf '%s FCM guard: physical-vs-Box DNS differential recovery rc=%s; reevaluate at next normal poll\n' \
      "$(date '+%F %T')" "$rc" >> "$OUTLOG"
  [ "$rc" -eq 0 ] || exit 1
  printf 'BOX_FCM_DNS_RECOVERY_TRIGGERED\n'
  exit 0
fi

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
