#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/bin/lib.sh"

DOWN_FILE=$RUNDIR/fcm_down_since.epoch
LAST_FILE=$RUNDIR/fcm_recover.epoch
ATTEMPT_FILE=$RUNDIR/fcm_recover.attempts
PATHLOG_FILE=$RUNDIR/fcm_path_fail_log.epoch
DNSLOG_FILE=$RUNDIR/fcm_dns_fail_log.epoch
DNSFAIL_FILE=$RUNDIR/fcm_dns_fail.epoch
DNSFLUSH_FILE=$RUNDIR/fcm_dns_flush.epoch
SOFT_RECONNECT_FILE=$RUNDIR/fcm_soft_reconnect.epoch
BYPASS_UID_FILE=$RUNDIR/fcm_bypass.uid
KEEPALIVE_FILE=$RUNDIR/fcm_keepalive.epoch
KEEPALIVE_INTERVAL=900
LOCK=$RUNDIR/fcm_guard.lock
LOCK_OWNER=$LOCK/owner
BOX_IPTABLES=/data/adb/box/scripts/box.iptables
IPTABLES_WAIT_SECONDS=5

proc_start_ticks() {
  pid=$1
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  stat_line=
  IFS= read -r stat_line < "/proc/$pid/stat" 2>/dev/null || return 1
  stat_tail=${stat_line##*) }
  [ "$stat_tail" != "$stat_line" ] || return 1
  set -- $stat_tail
  [ "$#" -ge 20 ] || return 1
  shift 19
  case "$1" in ''|*[!0-9]*) return 1;; esac
  printf '%s\n' "$1"
}

guard_lock_owner_alive() {
  [ -r "$LOCK_OWNER" ] || return 1
  read -r owner_pid owner_start < "$LOCK_OWNER" 2>/dev/null || return 1
  case "$owner_pid:$owner_start" in ''|*[!0-9:]*|:*|*:) return 1;; esac
  current_start=$(proc_start_ticks "$owner_pid") || return 1
  [ "$current_start" = "$owner_start" ]
}

guard_lock_age() {
  lock_mtime=$("$BB" stat -c %Y "$LOCK" 2>/dev/null)
  lock_now=$(date +%s)
  case "$lock_mtime:$lock_now" in
    *[!0-9:]*|:*|*:) echo 0;;
    *) echo $((lock_now-lock_mtime));;
  esac
}

acquire_guard_lock() {
  if mkdir "$LOCK" 2>/dev/null; then
    start=$(proc_start_ticks $$)
    [ -n "$start" ] || start=0
    printf '%s %s\n' "$$" "$start" > "$LOCK_OWNER"
    return 0
  fi
  guard_lock_owner_alive && return 1
  age=$(guard_lock_age)
  [ "$age" -ge 30 ] 2>/dev/null || return 1
  log_msg "FCM guard: recovering stale single-instance lock age=${age}s"
  rm -rf "$LOCK" 2>/dev/null || return 1
  if mkdir "$LOCK" 2>/dev/null; then
    start=$(proc_start_ticks $$)
    [ -n "$start" ] || start=0
    printf '%s %s\n' "$$" "$start" > "$LOCK_OWNER"
    return 0
  fi
  return 1
}

release_guard_lock() {
  [ -r "$LOCK_OWNER" ] || return 0
  read -r owner_pid owner_start < "$LOCK_OWNER" 2>/dev/null || return 0
  [ "$owner_pid" = "$$" ] || return 0
  rm -rf "$LOCK" 2>/dev/null || true
}

fcm_rule_count() {
  rule_uid=$1
  rules=$(iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL 2>/dev/null) || return 1
  printf '%s\n' "$rules" | awk -v uid="$rule_uid" '
    $1 == "-A" && $2 == "BOX_LOCAL" {
      owner=0; port=0; ret=0
      for (i=1; i<=NF; i++) {
        if ($i == "--uid-owner" && $(i+1) == uid) owner=1
        if ($i == "--dport" && $(i+1) == "5228:5230") port=1
        if ($i == "-j" && $(i+1) == "RETURN") ret=1
      }
      if (owner && port && ret) count++
    }
    END { print count+0 }
  '
}

delete_fcm_rules_for_uid() {
  delete_uid=$1
  delete_count=$(fcm_rule_count "$delete_uid") || return 1
  case "$delete_count" in ''|*[!0-9]*) delete_count=0;; esac
  while [ "$delete_count" -gt 0 ] 2>/dev/null; do
    iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -D BOX_LOCAL -p tcp -m owner --uid-owner "$delete_uid" \
      -m tcp --dport 5228:5230 -j RETURN >/dev/null 2>&1 || break
    delete_count=$((delete_count-1))
  done
}

box_manages_fcm_bypass() {
  [ -r "$BOX_IPTABLES" ] || return 1
  grep -q 'GMS_UID' "$BOX_IPTABLES" 2>/dev/null \
    && grep -q '5228:5230' "$BOX_IPTABLES" 2>/dev/null
}

ensure_fcm_uid_bypass() {
  # App UIDs are installation-state data and can change after a factory reset.
  # When the tested Box/TProxy chain exists, maintain one narrow FCM-only rule
  # instead of relying on a restored --uid-owner value from an older install.
  command -v iptables >/dev/null 2>&1 || return 0
  iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL >/dev/null 2>&1 || return 0
  gms_uid=$(pm list packages -U com.google.android.gms 2>/dev/null \
    | awk '$1 == "package:com.google.android.gms" { sub(/^uid:/, "", $2); print $2; exit }')
  case "$gms_uid" in ''|*[!0-9]*) return 0;; esac

  old_uid=$(cat "$BYPASS_UID_FILE" 2>/dev/null)
  case "$old_uid" in ''|*[!0-9]*) old_uid=;; esac
  if [ -n "$old_uid" ] && [ "$old_uid" != "$gms_uid" ]; then
    if delete_fcm_rules_for_uid "$old_uid"; then
      log_msg "FCM guard: removed stale managed Box FCM bypass old_uid=$old_uid"
    fi
  fi

  count=$(fcm_rule_count "$gms_uid") || return 0
  case "$count" in ''|*[!0-9]*) count=0;; esac
  if [ "$count" -eq 0 ] 2>/dev/null; then
    # Box For Root also installs the same narrow GMS rule on the validated
    # setup. During a chain rebuild there is a short interval after BOX_LOCAL
    # is flushed but before Box re-adds its rule. Do not race that window:
    # wait for the native owner first, then self-heal only if the rule is still
    # genuinely absent. Duplicate rules are harmless and are deliberately not
    # normalized here because delete/reinsert churn can interleave with Box.
    if box_manages_fcm_bypass; then
      retry=0
      while [ "$retry" -lt 3 ] 2>/dev/null; do
        sleep 1
        count=$(fcm_rule_count "$gms_uid") || return 0
        [ "$count" -gt 0 ] 2>/dev/null && break
        retry=$((retry+1))
      done
    fi
    if [ "$count" -eq 0 ] 2>/dev/null \
        && iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -I BOX_LOCAL 1 \
          -p tcp -m owner --uid-owner "$gms_uid" \
          -m tcp --dport 5228:5230 -j RETURN >/dev/null 2>&1; then
      log_msg "FCM guard: installed missing Box FCM-only bypass uid=$gms_uid ports=5228:5230"
    fi
  fi
  printf '%s\n' "$gms_uid" > "$BYPASS_UID_FILE"
  chmod 600 "$BYPASS_UID_FILE" 2>/dev/null || true
}

fcm_state() {
  line=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'Is client connected:' || true)
  case "$line" in
    *true*)  echo connected ;;
    *false*) echo disconnected ;;
    *)       echo unknown ;;
  esac
}

connected_keepalive() {
  ka_now=$1
  ka_last=$(cat "$KEEPALIVE_FILE" 2>/dev/null)
  case "$ka_last" in ''|*[!0-9]*) ka_last=0;; esac
  [ $((ka_now-ka_last)) -ge "$KEEPALIVE_INTERVAL" ] 2>/dev/null || return 0
  printf '%s\n' "$ka_now" > "$KEEPALIVE_FILE"

  # GcmService can report connected=true while the underlying MCS socket has
  # already gone stale behind a mobile/NAT path. Sending Google's own native
  # heartbeat is a low-impact liveness probe: a healthy socket just sends the
  # heartbeat; a stale socket is closed and reconnected by GMS itself.
  before_endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  if ! "$BB" timeout 8 am broadcast --user 0 \
      -a com.google.android.intent.action.MCS_HEARTBEAT \
      -p com.google.android.gms >/dev/null 2>&1; then
    log_msg "FCM guard: proactive MCS heartbeat broadcast failed"
    return 1
  fi
  sleep 2

  after_state=$(fcm_state)
  after_endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  if [ "$after_state" = connected ] && [ "$before_endpoint" != "$after_endpoint" ]; then
    log_msg "FCM guard: proactive heartbeat exposed stale MCS; reconnected ${after_endpoint:-endpoint-unavailable}"
  elif [ "$after_state" != connected ]; then
    log_msg "FCM guard: proactive heartbeat left GcmService state=$after_state; normal recovery path will handle it"
  fi
  return 0
}

gcm_reconnect_alarm_pending() {
  run_timeout dumpsys alarm 2>/dev/null \
    | grep -Fq '*walarm*:com.google.android.intent.action.GCM_RECONNECT'
}

gcm_reconnect_scheduler_state() {
  # GcmService prints an ISO-8601-style relative duration. A negative
  # component (for example "in PT-7H-47M") means the scheduler still believes
  # a reconnect alarm is due even though its deadline is already in the past.
  # The 2026-09-05 incident showed the corresponding AlarmManager entry can
  # disappear completely while this stale internal deadline remains.
  scheduler_line=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'Reconnect Scheduler Alarm:' || true)
  case "$scheduler_line" in
    *'in PT-'*) echo overdue; return 0 ;;
    *'in PT'*)  echo scheduled; return 0 ;;
  esac
  if gcm_reconnect_alarm_pending; then
    echo scheduled
  else
    echo missing
  fi
}

soft_reconnect_if_stalled() {
  soft_now=$1
  soft_outage=$2
  [ "$soft_outage" -ge 120 ] 2>/dev/null || return 1

  scheduler_state=$(gcm_reconnect_scheduler_state)
  case "$scheduler_state" in
    overdue) soft_reason=overdue-scheduler ;;
    missing)
      # Avoid racing the short window between one reconnect attempt and GMS
      # registering its next alarm. A completely missing scheduler is only
      # considered stuck after five minutes of continuous disconnection.
      [ "$soft_outage" -ge 300 ] 2>/dev/null || return 1
      soft_reason=missing-alarm
      ;;
    *) return 1 ;;
  esac

  soft_last=$(cat "$SOFT_RECONNECT_FILE" 2>/dev/null)
  case "$soft_last" in ''|*[!0-9]*) soft_last=0;; esac
  [ $((soft_now-soft_last)) -ge 300 ] 2>/dev/null || return 1
  printf '%s\n' "$soft_now" > "$SOFT_RECONNECT_FILE"

  # This is the same reconnect event GMS normally receives from its own
  # AlarmManager PendingIntent. It does not kill/restart Play services and is
  # safe to use while DNS is unhealthy: a failed attempt simply lets GMS
  # rebuild its normal reconnect backoff/alarm state.
  log_msg "FCM guard: reconnect scheduler $soft_reason outage=${soft_outage}s; sending soft GCM_RECONNECT"
  if ! "$BB" timeout 8 am broadcast --user 0 \
      -a com.google.android.intent.action.GCM_RECONNECT \
      -p com.google.android.gms >/dev/null 2>&1; then
    log_msg "FCM guard: soft GCM_RECONNECT broadcast failed"
    return 1
  fi
  sleep 8

  if [ "$(fcm_state)" = "connected" ]; then
    endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
      | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
    log_msg "FCM guard: soft reconnect recovered ${endpoint:-endpoint-unavailable}"
    rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
    return 0
  fi

  log_msg "FCM guard: soft reconnect delivered but GcmService remains disconnected"
  return 1
}

fcm_path_ready() {
  # Use the same Android resolver path as GMS. A direct nslookup from the
  # module shell is not an independent probe on TProxy systems because Box may
  # hijack it back through the same sing-box DNS policy.
  ip=$(android_resolve_mtalk 2>/dev/null || true)
  [ -n "$ip" ] || return 1
  for port in 5228 5229 5230; do
    if "$BB" timeout 6 "$BB" nc -z -w 4 "$ip" "$port" >/dev/null 2>&1; then
      printf '%s %s %s\n' android "$ip" "$port"
      return 0
    fi
  done
  return 1
}

android_resolve_mtalk() {
  # Deliberately use Android's libc/netd resolver path instead of direct
  # nslookup. The latter can succeed against a configured upstream while GMS
  # itself is still receiving UNKNOWN_HOST through Android's resolver chain.
  out=$(run_timeout /system/bin/ping -c 1 -W 1 mtalk.google.com 2>&1 || true)
  ip=$(printf '%s\n' "$out" | awk '
    /PING[[:space:]]+mtalk[.]google[.]com/ {
      if (match($0, /\([0-9][0-9.]*\)/)) {
        value=substr($0, RSTART+1, RLENGTH-2)
        if (split(value, octets, ".") == 4) { print value; exit }
      }
    }
  ')
  case "$ip" in *.*.*.*) printf '%s\n' "$ip"; return 0;; esac
  return 1
}

recent_gms_unknown_host_epoch() {
  # gtalk_connection packs connection_error in bits 8..15; Android's event
  # definition assigns value 3 to UNKNOWN_HOST. Only recent evidence blocks a
  # process restart, so an old historical event cannot suppress recovery.
  line=$(run_timeout logcat -b events -d -v epoch -t 400 2>/dev/null \
    | grep 'gtalk_connection' | tail -n 1 || true)
  [ -n "$line" ] || return 1
  pair=$(printf '%s\n' "$line" | awk '
    {
      ts=$1; sub(/[.].*$/, "", ts)
      if (ts !~ /^[0-9]+$/) next
      for (i=NF; i>=1; i--) {
        v=$i; gsub(/[^0-9]/, "", v)
        if (v ~ /^[0-9]+$/) { print ts " " v; exit }
      }
    }
  ')
  [ -n "$pair" ] || return 1
  event_epoch=${pair%% *}
  status=${pair#* }
  case "$event_epoch:$status" in *[!0-9:]*|:*|*:) return 1;; esac
  err=$(( (status / 256) % 256 ))
  [ "$err" -eq 3 ] 2>/dev/null || return 1
  event_now=$(date +%s)
  event_age=$((event_now-event_epoch))
  [ "$event_age" -ge 0 ] 2>/dev/null || return 1
  [ "$event_age" -le 900 ] 2>/dev/null || return 1
  printf '%s\n' "$event_epoch"
}

remember_dns_failure() {
  stamp=$1
  case "$stamp" in ''|*[!0-9]*) return 0;; esac
  old=$(cat "$DNSFAIL_FILE" 2>/dev/null)
  case "$old" in ''|*[!0-9]*) old=0;; esac
  [ "$stamp" -gt "$old" ] 2>/dev/null && printf '%s\n' "$stamp" > "$DNSFAIL_FILE"
}

dns_netids() {
  run_timeout dumpsys dnsresolver 2>/dev/null | awk '
    /NetId:/ {
      for (i=1; i<=NF; i++) {
        if ($i == "NetId:" && $(i+1) ~ /^[0-9]+$/ && !seen[$(i+1)]++) print $(i+1)
      }
    }
  '
}

flush_android_dns() {
  flush_now=$1
  last_flush=$(cat "$DNSFLUSH_FILE" 2>/dev/null)
  case "$last_flush" in ''|*[!0-9]*) last_flush=0;; esac
  [ $((flush_now-last_flush)) -ge 300 ] 2>/dev/null || return 0
  printf '%s\n' "$flush_now" > "$DNSFLUSH_FILE"

  flushed=0
  for netid in $(dns_netids); do
    if command -v ndc >/dev/null 2>&1; then
      ndc_out=$("$BB" timeout 5 ndc resolver flushnet "$netid" 2>&1)
      ndc_rc=$?
      case "$ndc_out" in
        *'Command not recognized'*|*'Failure calling service'*|*'Failed transaction'*|*'Exception'*) ndc_ok=0 ;;
        [45][0-9][0-9]' '*) ndc_ok=0 ;;
        *) [ "$ndc_rc" -eq 0 ] 2>/dev/null && ndc_ok=1 || ndc_ok=0 ;;
      esac
      if [ "$ndc_ok" -eq 1 ] 2>/dev/null; then
        flushed=$((flushed+1))
        continue
      fi
    fi
    cmd_out=$("$BB" timeout 5 cmd netd resolver flushnet "$netid" 2>&1)
    cmd_rc=$?
    case "$cmd_out" in
      *'Command not recognized'*|*'Failure calling service'*|*'Failed transaction'*|*'Exception'*) cmd_ok=0 ;;
      *) [ "$cmd_rc" -eq 0 ] 2>/dev/null && cmd_ok=1 || cmd_ok=0 ;;
    esac
    if [ "$cmd_ok" -eq 1 ] 2>/dev/null; then
      flushed=$((flushed+1))
    fi
  done
  if [ "$flushed" -gt 0 ] 2>/dev/null; then
    log_msg "FCM guard: flushed Android DNS cache networks=$flushed"
  else
    log_msg "FCM guard: Android DNS cache flush unsupported/no active resolver netId; restart remains blocked while DNS is unhealthy"
  fi
}

rate_limited_dns_log() {
  dns_now=$1
  shift
  last=$(cat "$DNSLOG_FILE" 2>/dev/null)
  case "$last" in ''|*[!0-9]*) last=0;; esac
  if [ $((dns_now-last)) -ge 900 ] 2>/dev/null; then
    printf '%s\n' "$dns_now" > "$DNSLOG_FILE"
    log_msg "FCM guard: $*"
  fi
}

rate_limited_path_log() {
  now=$1
  last=$(cat "$PATHLOG_FILE" 2>/dev/null)
  case "$last" in ''|*[!0-9]*) last=0;; esac
  if [ $((now-last)) -ge 900 ] 2>/dev/null; then
    echo "$now" > "$PATHLOG_FILE"
    log_msg "FCM guard: GcmService disconnected but mtalk TCP path unavailable; no GMS restart"
  fi
}

# Polling and the event worker can wake at the same time. Serialize the whole
# guard so they cannot duplicate firewall rules or race restart accounting.
acquire_guard_lock || exit 0
trap 'release_guard_lock' EXIT HUP INT TERM

# Keep the port-only Box exception self-healing across Box rule rebuilds and
# clean installs before evaluating the GCM state.
ensure_fcm_uid_bypass

now=$(date +%s)
state=$(fcm_state)
case "$state" in
  connected)
    connected_keepalive "$now" || true

    # The heartbeat probe itself can expose a half-open MCS session. Re-read
    # GcmService before clearing outage metadata; otherwise the disconnect
    # discovered by the heartbeat is immediately forgotten until a later pass.
    state=$(fcm_state)
    if [ "$state" = connected ]; then
      rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
      exit 0
    fi
    [ "$state" = unknown ] && exit 0
    log_msg "FCM guard: keepalive exposed disconnected MCS; entering recovery path"
    ;;
  unknown)
    # Fail closed: diagnostics failure must never trigger process intervention.
    exit 0
    ;;
esac

# Explicitly disconnected from GCM/FCM from here on. On newer GMS builds the
# GcmService host can be com.google.android.gms instead of the historical
# com.google.android.gms.persistent process.
gpid=$(pidof com.google.android.gms.persistent 2>/dev/null | awk '{print $1}')
[ -n "$gpid" ] || gpid=$(pidof com.google.android.gms 2>/dev/null | awk '{print $1}')
spid=$(pidof sing-box 2>/dev/null | awk '{print $1}')
[ -n "$gpid" ] && [ -n "$spid" ] || exit 0

if [ ! -f "$DOWN_FILE" ]; then
  echo "$now" > "$DOWN_FILE"
  log_msg "FCM guard: GcmService disconnected; starting outage timer"
  exit 0
fi

down_since=$(cat "$DOWN_FILE" 2>/dev/null)
case "$down_since" in ''|*[!0-9]*) down_since=$now;; esac
outage=$((now-down_since))

# DNS failures are actionable earlier than a process restart. A recent
# UNKNOWN_HOST emitted by GMS itself is authoritative evidence that killing
# gms.persistent is the wrong layer to repair. Refresh resolver caches at a
# bounded rate, then leave Google's reconnect logic intact.
if [ "$outage" -ge 60 ] 2>/dev/null; then
  unknown_epoch=$(recent_gms_unknown_host_epoch 2>/dev/null || true)
  if [ -n "$unknown_epoch" ]; then
    unknown_age=$((now-unknown_epoch))
    if [ "$unknown_age" -lt 600 ] 2>/dev/null; then
      remember_dns_failure "$unknown_epoch"
      flush_android_dns "$now"
      rate_limited_dns_log "$now" "GMS reported UNKNOWN_HOST ${unknown_age}s ago; DNS remediation only, no GMS restart"
      soft_reconnect_if_stalled "$now" "$outage" || true
      exit 0
    fi
  fi

  android_ip=$(android_resolve_mtalk 2>/dev/null || true)
  if [ -z "$android_ip" ]; then
    remember_dns_failure "$now"
    flush_android_dns "$now"
    rate_limited_dns_log "$now" "Android resolver cannot resolve mtalk.google.com; DNS remediation only, no GMS restart"
    soft_reconnect_if_stalled "$now" "$outage" || true
    exit 0
  fi

  last_dns_fail=$(cat "$DNSFAIL_FILE" 2>/dev/null)
  case "$last_dns_fail" in ''|*[!0-9]*) last_dns_fail=0;; esac
  if [ "$last_dns_fail" -gt 0 ] 2>/dev/null && [ $((now-last_dns_fail)) -lt 300 ] 2>/dev/null; then
    rate_limited_dns_log "$now" "Android resolver recovered mtalk=$android_ip but is inside 300s stability grace; no GMS restart"
    exit 0
  fi
fi

# A healthy resolver is not enough if GMS lost its own reconnect alarm. Repair
# that scheduler state before considering a process restart. The live incident
# on 2026-09-05 recovered in seconds from this broadcast with the same GMS PID.
if soft_reconnect_if_stalled "$now" "$outage"; then
  exit 0
fi

# Give Google's own reconnect logic five minutes before intervention. The old
# 10m grace plus 30/60/120m retry schedule could turn one stuck MCS state into
# a multi-hour push outage.
[ "$outage" -ge 300 ] 2>/dev/null || exit 0

# Distinguish a stuck GMS/MCS client from a genuine FCM path outage. Restarting
# GMS cannot repair an unreachable network and would only waste battery.
path=$(fcm_path_ready 2>/dev/null || true)
if [ -z "$path" ]; then
  rate_limited_path_log "$now"
  exit 0
fi
rm -f "$PATHLOG_FILE" 2>/dev/null || true

attempts=$(cat "$ATTEMPT_FILE" 2>/dev/null)
case "$attempts" in ''|*[!0-9]*) attempts=0;; esac
last=$(cat "$LAST_FILE" 2>/dev/null)
case "$last" in ''|*[!0-9]*) last=0;; esac

# Fast early recovery, progressively reducing churn. Persistent failures are
# capped at one intervention per hour instead of either hammering GMS or
# waiting two hours between attempts.
case "$attempts" in
  0) min_gap=0 ;;
  1) min_gap=300 ;;
  2) min_gap=600 ;;
  3) min_gap=1200 ;;
  4|5) min_gap=1800 ;;
  *) min_gap=3600 ;;
esac
[ $((now-last)) -ge "$min_gap" ] 2>/dev/null || exit 0

resolver=${path%% *}
rest=${path#* }
ip=${rest%% *}
port=${rest##* }
android_ip=$(android_resolve_mtalk 2>/dev/null || true)
[ -n "$android_ip" ] || exit 0
log_msg "FCM guard: outage=${outage}s fcm_path=ok resolver=$resolver endpoint=$ip:$port android_resolver=$android_ip; restarting GMS-host pid=$gpid attempt=$((attempts+1))"
echo "$now" > "$LAST_FILE"
echo $((attempts+1)) > "$ATTEMPT_FILE"
kill -TERM "$gpid" 2>/dev/null || exit 0
sleep 20

state2=$(fcm_state)
if [ "$state2" = "connected" ]; then
  rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
  newpid=$(pidof com.google.android.gms.persistent 2>/dev/null | awk '{print $1}')
  [ -n "$newpid" ] || newpid=$(pidof com.google.android.gms 2>/dev/null | awk '{print $1}')
  endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  log_msg "FCM guard: recovered newpid=${newpid:-unknown} ${endpoint:-endpoint-unavailable}"
else
  log_msg "FCM guard: restart issued but GcmService state=$state2; retry schedule retained"
fi
