#!/system/bin/sh
# alpha18: bounded, read-only FCM DNS failure flight recorder.
# Invoked ONLY by fcm_guard when its GMS-UID Android DNS check is currently
# unresolved AND the actual GcmService outage has lasted >= 15 minutes.
# It never changes the network, sends broadcasts, restarts processes or writes
# to Box/Android settings. No independent poller, wakeup or timer is added.
RUNDIR=/data/adb/fcm_unified_guard
BOX=/data/adb/box
DIAGDIR=$RUNDIR/dns_differential
LAST=$DIAGDIR/last_probe.epoch
STATE=$DIAGDIR/latest.tsv
HISTORY=$DIAGDIR/history.tsv
OUTAGE=${1:-}
case "$OUTAGE" in ''|*[!0-9]*) exit 0;; esac
read -r REAL_OUTAGE < "$RUNDIR/fcm_down_since.epoch" 2>/dev/null || exit 0
[ "$OUTAGE" = "$REAL_OUTAGE" ] || exit 0
NOW=$(date +%s)
AGE=$((NOW-OUTAGE))
[ "$AGE" -ge 900 ] && [ "$AGE" -le 86400 ] || exit 0
mkdir -p "$DIAGDIR" 2>/dev/null || exit 0
OLD=$(cat "$LAST" 2>/dev/null)
case "$OLD" in ''|*[!0-9]*) OLD=0;; esac
# Only the existing guard invokes this and already serializes its work.
[ $((NOW-OLD)) -ge 900 ] || exit 0
printf '%s\n' "$NOW" > "$LAST"

gate=unknown
iface=none
gms=not_tested
upstream=not_tested
box=missing
box_age=unknown
box_dns=absent
cooldown=unknown

# Record a final verdict on all exits with a bounded, fixed-schema text row.
record() {
  row=$(printf '%s\toutage_sec=%s\tgate=%s\tdefault_iface=%s\tgms_libc=%s\tupstream_dns=%s\tbox=%s\tbox_age=%s\tdns_capture=%s\tlimit=%s' "$(date '+%F %T %z')" "$AGE" "$gate" "$iface" "$gms" "$upstream" "$box" "$box_age" "$box_dns" "$cooldown")
  printf '%s\n' "$row" > "$STATE.tmp.$$"
  mv -f "$STATE.tmp.$$" "$STATE"
  printf '%s\n' "$row" >> "$HISTORY"
  busybox tail -n 96 "$HISTORY" > "$HISTORY.tmp.$$" 2>/dev/null &&
    mv -f "$HISTORY.tmp.$$" "$HISTORY"
  rm -f "$HISTORY.tmp.$$" 2>/dev/null || true
}
trap 'record' EXIT

if [ -e /data/adb/modules/box_for_root/disable ] || [ -e "$BOX/manual" ]; then
  gate=user_disabled_box
  exit 0
fi

PID=$(cat "$BOX/run/box.pid" 2>/dev/null)
case "$PID" in ''|*[!0-9]*) gate=box_pid_missing; exit 0;; esac
[ -r "/proc/$PID/comm" ] || { gate=box_process_missing; exit 0; }
read -r NAME < "/proc/$PID/comm" 2>/dev/null || { gate=box_comm_unreadable; exit 0; }
[ "$NAME" = sing-box ] && kill -0 "$PID" 2>/dev/null || { gate=box_not_running; exit 0; }
box=alive

[ -x "$BOX/scripts/box.service" ] && [ -r "$BOX/run/sing-box.log" ] ||
  { gate=box_service_unavailable; exit 0; }

UID=$(cat "$RUNDIR/fcm_bypass.uid" 2>/dev/null)
case "$UID" in ''|*[!0-9]*) gate=gms_uid_missing; exit 0;; esac
[ "$UID" -ge 10000 ] || { gate=gms_uid_invalid; exit 0; }
ACTUAL_UID=$(pm list packages -U com.google.android.gms 2>/dev/null |
  busybox awk '$1=="package:com.google.android.gms" {sub(/^uid:/,"",$2);print $2;exit}')
[ "$ACTUAL_UID" = "$UID" ] || { gate=gms_uid_mismatch; exit 0; }

if iptables -w 5 -t mangle -S BOX_LOCAL 2>/dev/null |
  grep -Eq -- '^-A BOX_LOCAL .*udp .*--dport 53 .*MARK'; then
  box_dns=present
else
  gate=box_dns_capture_missing
  exit 0
fi

ROUTE=$(ip -4 route get 223.5.5.5 2>/dev/null) ||
  { gate=no_ipv4_route; exit 0; }
iface=$(printf '%s\n' "$ROUTE" | busybox awk 'NR==1 {for(i=1;i<NF;i++)if($i=="dev"){print $(i+1);exit}}')
[ -n "$iface" ] || { gate=route_without_iface; exit 0; }

STAT=
IFS= read -r STAT < "/proc/$PID/stat" 2>/dev/null || { gate=box_proc_stat_unavailable; exit 0; }
TAIL=${STAT##*) }
[ "$TAIL" != "$STAT" ] || { gate=box_proc_stat_invalid; exit 0; }
set -- $TAIL
[ "$#" -ge 20 ] || { gate=box_proc_stat_short; exit 0; }
shift 19
TICKS=$1
HZ=$(getconf CLK_TCK 2>/dev/null)
case "$TICKS:$HZ" in ''|*[!0-9:]*|*:|*:0) gate=box_start_unknown; exit 0;; esac
read -r UPTIME ignored < /proc/uptime || { gate=uptime_unknown; exit 0; }
UPTIME=${UPTIME%%.*}
box_age=$((UPTIME-TICKS/HZ))
[ "$box_age" -ge 1200 ] || { gate=box_recently_started; exit 0; }

# This diagnostic reads only the existing restart counters; it never spends
# them. Keep it aligned with alpha17's one/outage and 6-hour fail-closed rule.
LAST_FALLBACK=$(cat "$RUNDIR/box_dns_repair/fallback_last.epoch" 2>/dev/null)
case "$LAST_FALLBACK" in ''|*[!0-9]*) LAST_FALLBACK=0;; esac
if [ $((NOW-LAST_FALLBACK)) -lt 21600 ]; then
  cooldown=6h
elif [ "$(cat "$RUNDIR/box_dns_repair/fallback_outage.epoch" 2>/dev/null)" = "$OUTAGE" ]; then
  cooldown=one_per_outage
else
  cooldown=ready
fi

# GMS UID's libc resolution behavior is isolated from root's path; a ping
# header containing an IPv4 address is sufficient to prove DNS succeeded.
LOOKUP=$(busybox timeout 7 su -s /system/bin/sh "$UID" \
  -c '/system/bin/ping -c 1 -W 1 mtalk.google.com' 2>&1)
if printf '%s\n' "$LOOKUP" | grep -Eq '^PING[[:space:]].*\([0-9][0-9.]*\)'; then
  gms=resolved
  gate=gms_dns_already_restored
  exit 0
fi
if printf '%s\n' "$LOOKUP" |
  grep -Eqi 'unknown host|bad address|name or service not known|temporary failure in name resolution'; then
  gms=lookup_error
else
  gms=indeterminate
  gate=gms_query_not_conclusive
  exit 0
fi

# alpha23: Root/GID0 explicit DNS is BOX-CAPTURED by this device's
# TProxy rule; it is not evidence the physical carrier upstream works.
# Only call GID3005 queries physical when Box proves that UID0/GID3005
# RETURN precedes UDP53 MARK. GMS uses the real Android libc resolver.
if ! iptables -w 5 -t mangle -S BOX_LOCAL 2>/dev/null |
    grep -Fq -- '-m owner --uid-owner 0 --gid-owner 3005 -j RETURN'; then
  upstream=unknown
  gate=physical_upstream_bypass_unverified
  exit 0
fi
if ! ip -4 rule show 2>/dev/null | grep -Fq 'fwmark 0x1000000/0x1000000 lookup 2024' ||
   ! ip -4 route show table 2024 2>/dev/null | grep -Fq 'local default dev lo'; then
  upstream=unknown
  gate=box_egress_not_proven
  exit 0
fi

for SERVER in 223.5.5.5 61.139.2.69; do
  ANSWER=$(busybox timeout 8 su -g 3005 0 -c \
    "busybox timeout 6 busybox nslookup mtalk.google.com $SERVER" 2>/dev/null)
  if printf '%s\n' "$ANSWER" | grep -Fq 'Name:      mtalk.google.com'; then
    upstream=physical_direct_resolved
    break
  fi
done
if [ "$upstream" != physical_direct_resolved ]; then
  upstream=physical_direct_failed
  gate=physical_upstream_or_transport_unavailable
  exit 0
fi

box_answer=failed
for SERVER in 223.5.5.5 61.139.2.69; do
  ANSWER=$(busybox timeout 8 su -g 0 0 -c \
    "busybox timeout 6 busybox nslookup mtalk.google.com $SERVER" 2>/dev/null)
  if printf '%s\n' "$ANSWER" | grep -Fq 'Name:      mtalk.google.com'; then
    box_answer=resolved
    break
  fi
done
if [ "$box_answer" = resolved ]; then
  gate=both_dns_paths_work_gms_native_fails_not_box_proven
elif [ "$cooldown" != ready ]; then
  gate=box_path_fault_but_recovery_rate_limited
else
  gate=physical_dns_ok_box_captured_dns_failed
fi
exit 0
