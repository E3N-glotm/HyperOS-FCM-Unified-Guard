#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/bin/lib.sh"

DOWN_FILE=$RUNDIR/fcm_down_since.epoch
LAST_FILE=$RUNDIR/fcm_recover.epoch
ATTEMPT_FILE=$RUNDIR/fcm_recover.attempts
PATHLOG_FILE=$RUNDIR/fcm_path_fail_log.epoch
DNSLOG_FILE=$RUNDIR/fcm_dns_fail_log.epoch
DNSFAIL_FILE=$RUNDIR/fcm_dns_fail.epoch
DNSOK_FILE=$RUNDIR/fcm_dns_recovered_since.epoch
DNSFLUSH_FILE=$RUNDIR/fcm_dns_flush.epoch
DNSFLUSH_SCOPE_FILE=$RUNDIR/fcm_dns_flush_scope.signature
DNSFLUSH_OUTAGE_FILE=$RUNDIR/fcm_dns_flush_outage.epoch
DNSLATE_FILE=$RUNDIR/fcm_dns_late_attempt.epoch
DNSLATE_FAILED_FILE=$RUNDIR/fcm_dns_late_confirmed_failed.state
SOFT_RECONNECT_FILE=$RUNDIR/fcm_soft_reconnect.epoch
BYPASS_UID_FILE=$RUNDIR/fcm_bypass.uid
KEEPALIVE_FILE=$RUNDIR/fcm_keepalive.epoch
KEEPALIVE_INTERVAL=600
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
  awk -v uid="$rule_uid" '
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
  ' <<EOF
$rules
EOF
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
  # Retain only two short lines; never pass a full dumpsys as an argument.
  snapshot=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | awk '/^[[:space:]]*connected=/ && !ep++ {print}
           /Is client connected:/ && !st++ {print}' || true)
  line=$(printf '%s\n' "$snapshot" | grep -m1 'Is client connected:' || true)
  case "$line" in
    *true*)  observed_state=connected ;;
    *false*) observed_state=disconnected ;;
    *)       observed_state=unknown ;;
  esac
  printf '%s\n' "$snapshot" | awk '/^[[:space:]]*connected=/ {sub(/^[[:space:]]*/, ""); print; exit}' \
    > "$RUNDIR/fcm-observed.endpoint"
  printf '%s %s\n' "$observed_state" "${now:-0}" > "$RUNDIR/fcm-observed.state"
  echo "$observed_state"
}

connected_keepalive() {
  # alpha12: observe a healthy GMS connection without sending MCS_HEARTBEAT.
  # In real 2026-11-02/03 logs nearly every ten-minute forced heartbeat
  # changed the MCS endpoint. This is disruption, NOT evidence of stale MCS.
  # Google Play services already schedules its own heartbeat (~25 min).
  KEEPALIVE_PROBED=0
  # alpha30: scope kernel-level TCP probes to the verified MCS socket.
  # No forced GMS heartbeat, no extra wakeup worker, no global TCP changes.
  if [ -x "$MODDIR/bin/fcmu_socket_keepalive" ] && [ -r "$MODDIR/bin/fcm_socket_keepalive.sh" ]; then
    . "$MODDIR/bin/fcm_socket_keepalive.sh"
    fcm_socket_keepalive "$1" || true
  fi
  ka_now=$1
  ka_last=$(cat "$KEEPALIVE_FILE" 2>/dev/null)
  case "$ka_last" in ''|*[!0-9]*) ka_last=0;; esac
  [ $((ka_now-ka_last)) -ge "$KEEPALIVE_INTERVAL" ] 2>/dev/null || return 0
  printf '%s\n' "$ka_now" > "$KEEPALIVE_FILE"

  # Passive check only. The ordinary 120-second guard observes disconnections
  # and the bounded soft GCM_RECONNECT path handles actual outages.
  healthy_endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  if ! printf '%s\n' "$healthy_endpoint" | grep -Eq 'connected=[^[:space:]]+.*port=[0-9]+'; then
    log_msg "FCM guard: alpha12 passive MCS check has no endpoint; leaving native GMS heartbeat undisturbed"
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

# A transient connected=true plus a formatted endpoint does not prove a
# usable MCS socket. Verify the endpoint against the kernel's established
# socket and the *real GMS UID* before clearing an outage after GCM_RECONNECT.
fcm_mcs_endpoint_socket_ready() {
  ss_endpoint=$1
  case "$ss_endpoint" in
    connected=mtalk.google.com/*,port=*|connected=alt[0-9]*-mtalk.google.com/*,port=*) ;;
    *) return 1;;
  esac
  ss_peer=${ss_endpoint#*/}
  ss_peer=${ss_peer%,port=*}
  ss_peer=${ss_peer#\[}
  ss_peer=${ss_peer%\]}
  ss_peer=${ss_peer#::ffff:}
  ss_port=${ss_endpoint##*,port=}
  case "$ss_peer" in ''|*[!0-9a-fA-F:.]*) return 1;; esac
  case "$ss_port" in 5228|5229|5230|443) ;; *) return 1;; esac
  command -v ss >/dev/null 2>&1 || return 1
  [ -r "$MODDIR/bin/fcm_socket_keepalive.sh" ] || return 1
  ss_uid=$(gms_uid_for_probe 2>/dev/null) || return 1
  . "$MODDIR/bin/fcm_socket_keepalive.sh"
  [ -n "$(run_timeout ss -Htnpe state established "( dport = :$ss_port )" 2>/dev/null \
      | fcm_mcs_socket_tuple "$ss_peer" "$ss_port" "$ss_uid")" ]
}

soft_reconnect_if_stalled() {
  soft_now=$1
  soft_outage=$2
  # The soft native GMS reconnect is safe well before any process restart.
  [ "$soft_outage" -ge 90 ] 2>/dev/null || return 1

  scheduler_state=$(gcm_reconnect_scheduler_state)
  soft_gap=180
  case "$scheduler_state" in
    overdue) soft_reason=overdue-scheduler ;;
    scheduled)
      # During mobile idle, an apparently scheduled GMS reconnect alarm may
      # remain deferred for tens of minutes. Do not equate scheduled with
      # making progress: after 120 seconds of observed disconnection, send
      # Google's own soft GCM_RECONNECT (NOT a GMS process restart).
      # Leave strict DNS/TCP checks for the independent SIGTERM fallback.
      [ "$soft_outage" -ge 120 ] 2>/dev/null || return 1
      soft_reason=scheduled-alarm-stalled-native-reconnect
      # Use existing event/poll wakes. Avoid alarms, wakelocks or busy loops.
      # Throttle repeated soft requests to one per five minutes.
      soft_gap=300
      ;;
    missing)
      # Avoid racing the short window between one reconnect attempt and GMS
      # registering its next alarm. A missing scheduler after 90 seconds
      # merits one low-impact soft reconnect attempt.
      [ "$soft_outage" -ge 90 ] 2>/dev/null || return 1
      soft_reason=missing-alarm
      ;;
    *) return 1 ;;
  esac

  # alpha18: once a DNS outage has persisted for 15 minutes, an MCS
  # reconnect broadcast cannot fix name resolution. Preserve fast initial
  # attempts, then reduce repeated ineffective broadcasts from ~5 to 30m.
  # Actual DNS recovery is still checked on every existing guard wake.
  if [ "${3:-}" = dns-failed ] && [ "$soft_outage" -ge 900 ] 2>/dev/null; then
    soft_gap=1800
    soft_reason="$soft_reason-dns-unavailable"
  fi

  soft_last=$(cat "$SOFT_RECONNECT_FILE" 2>/dev/null)
  case "$soft_last" in ''|*[!0-9]*) soft_last=0;; esac
  [ $((soft_now-soft_last)) -ge "$soft_gap" ] 2>/dev/null || return 1
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

  # Do not mistake a transient GcmService connected=true for an established
  # MCS socket. This was the 05:38:47 false-success of 2026-11-01.
  soft_state=$(fcm_state)
  endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  if [ "$soft_state" = connected ] \
      && fcm_mcs_endpoint_socket_ready "$endpoint"; then
    log_msg "FCM guard: soft reconnect MCS socket verified ${endpoint}"
    rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$DNSOK_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
    return 0
  fi

  log_msg "FCM guard: soft reconnect unverified state=$soft_state ${endpoint:-endpoint-unavailable}; outage timer retained"
  return 1
}

gms_uid_for_probe() {
  # Root's TCP checks may pass through Box/TProxy even when GMS's UID-bound
  # direct 5228 bypass cannot reach the same IP. Resolve the real package UID.
  probe_uid=$(cat "$BYPASS_UID_FILE" 2>/dev/null)
  case "$probe_uid" in ''|*[!0-9]*)
    probe_uid=$(pm list packages -U com.google.android.gms 2>/dev/null \
      | awk '$1 == "package:com.google.android.gms" { sub(/^uid:/, "", $2); print $2; exit }')
    ;;
  esac
  case "$probe_uid" in ''|*[!0-9]*) return 1;; esac
  printf '%s\n' "$probe_uid"
}

gms_uid_tcp_ready() {
  probe_ip=$1
  probe_port=$2
  probe_uid=$(gms_uid_for_probe) || return 1
  # MagiskSU switches the socket owner to the GMS UID, matching per-UID
  # firewall / routing exemptions. If this cannot run, fail closed instead
  # of trusting a root/proxy socket and killing a healthy Google service.
  command -v su >/dev/null 2>&1 || return 1
  "$BB" timeout 7 su -s /system/bin/sh "$probe_uid" -c \
    "/system/bin/toybox nc -z -w 4 $probe_ip $probe_port >/dev/null 2>&1"
}

fcm_path_ready() {
  # The verified GMS process may use 443 with an alternate FCM host.
  # Never permit arbitrary 443 traffic to count as an MCS path proof.
  for host in mtalk.google.com alt1-mtalk.google.com alt2-mtalk.google.com alt3-mtalk.google.com; do
    ip=$(android_resolve_gms_domain "$host" 2>/dev/null || true)
    [ -n "$ip" ] || continue
    if [ "$host" = mtalk.google.com ]; then ports="5228 5229 5230 443"
    else ports="443 5228"; fi
    for port in $ports; do
      if gms_uid_tcp_ready "$ip" "$port"; then
        printf 'gms-uid:%s %s %s\n' "$host" "$ip" "$port"
        return 0
      fi
    done
  done
  return 1
}

android_resolve_gms_domain() {
  host=$1
  case "$host" in mtalk.google.com|alt[0-9]-mtalk.google.com) ;; *) return 1;; esac
  uid=$(gms_uid_for_probe 2>/dev/null || true)
  case "$uid" in ''|*[!0-9]*) return 1;; esac
  command -v su >/dev/null 2>&1 || return 1
  out=$(run_timeout su -s /system/bin/sh "$uid" -c \
    "/system/bin/ping -c 1 -W 1 $host" 2>&1 || true)
  ip=$(printf '%s\n' "$out" | awk '
    /^PING[[:space:]]+[^[:space:]]+[[:space:]]/ {
      if (match($0,/\([0-9][0-9.]*\)/)) {
        value=substr($0,RSTART+1,RLENGTH-2)
        if(split(value,o,".")==4) {
          valid=1
          for (i=1;i<=4;i++) if(o[i]!~/^[0-9]+$/||o[i]>255) valid=0
          if(valid){print value;exit}
        }
      }
    }
  ')
  case "$ip" in *.*.*.*) printf '%s\n' "$ip"; return 0;; esac
  return 1
}

android_resolve_mtalk() {
  android_resolve_gms_domain mtalk.google.com
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

# Android 17 ships DNS Resolver as a separate Binder-backed Mainline service.
# The legacy 'ndc resolver flushnet' and 'cmd netd resolver flushnet'
# commands are unavailable on this firmware. In AOSP Android 17 the stable
# IDnsResolver AIDL declaration places flushNetworkCache(int netId) at
# transaction 11 (after the read-only isAlive at transaction 1). Never invoke
# an unknown transaction on a different SDK, and verify the live service and
# real netIds before one bounded, per-outage cache flush.
dnsresolver_binder_ready() {
  [ "$(getprop ro.build.version.sdk)" = 37 ] || return 1
  service list 2>/dev/null |
    grep -Fq 'dnsresolver: [android.net.IDnsResolver]' || return 1
  alive=$("$BB" timeout 5 service call dnsresolver 1 2>&1) || return 1
  printf '%s\n' "$alive" |
    grep -Eq '^Result: Parcel\([[:space:]]*00000000[[:space:]]+00000001([[:space:]]|$)'
}

dnsresolver_binder_flush_one() {
  cache_netid=$1
  case "$cache_netid" in ''|*[!0-9]*) return 1;; esac
  # AOSP: status 00000000 means Binder completed without an exception.
  # Treat all other replies (including transport success with an exception)
  # as failure; do not claim a cache flush.
  cache_reply=$("$BB" timeout 5 service call dnsresolver 11 i32 "$cache_netid" 2>&1) || return 1
  printf '%s\n' "$cache_reply" |
    grep -Eq "^Result: Parcel\\([[:space:]]*00000000[[:space:]]+'"
}

# Resolve *one* real current default network: old alpha22 looped through all
# stale/IMS/secondary resolver NetIds and repeated each time Android rotated
# the network IDs. Cache refresh cannot repair a transport/routing failure.
# If we cannot prove one default network with an active resolver cache, skip.
dns_active_default_netid() {
  default_id=$(run_timeout dumpsys connectivity 2>/dev/null | awk '
    $1 == "Active" && $2 == "default" && $3 == "network:" &&
      $4 ~ /^[0-9]+$/ { print $4; exit }
  ')
  case "$default_id" in ''|*[!0-9]*) return 1;; esac
  dns_netids | grep -Fxq "$default_id" || return 1
  printf '%s\n' "$default_id"
}

flush_android_dns() {
  flush_now=$1
  outage_stamp=$(cat "$DOWN_FILE" 2>/dev/null)
  case "$outage_stamp" in ''|*[!0-9]*) return 0;; esac

  # A successful flush has precisely one opportunity per confirmed outage.
  # Previously merely changing mobile NetIds gave the same failing DNS
  # transport another flush every ~30 minutes for hours, wasting work.
  [ "$(cat "$DNSFLUSH_OUTAGE_FILE" 2>/dev/null)" != "$outage_stamp" ] || return 0
  last_flush=$(cat "$DNSFLUSH_FILE" 2>/dev/null)
  case "$last_flush" in ''|*[!0-9]*) last_flush=0;; esac
  [ $((flush_now-last_flush)) -ge 300 ] 2>/dev/null || return 0

  active_id=$(dns_active_default_netid) || {
    log_msg "FCM guard: no proven current default DNS resolver cache; skip stale or IMS NetIds"
    return 0
  }

  printf '%s\n' "$flush_now" > "$DNSFLUSH_FILE"
  flushed=0
  binder_flushed=0

  if dnsresolver_binder_ready && dnsresolver_binder_flush_one "$active_id"; then
    flushed=1
    binder_flushed=1
  else
    # Legacy fallback remains for non-Android17 systems with supported ndc.
    if command -v ndc >/dev/null 2>&1; then
      ndc_out=$("$BB" timeout 5 ndc resolver flushnet "$active_id" 2>&1)
      ndc_rc=$?
      case "$ndc_out" in
        *'Command not recognized'*|*'Failure calling service'*|*'Failed transaction'*|*'Exception'*) ndc_ok=0 ;;
        [45][0-9][0-9]' '*) ndc_ok=0 ;;
        *) [ "$ndc_rc" -eq 0 ] 2>/dev/null && ndc_ok=1 || ndc_ok=0 ;;
      esac
      [ "$ndc_ok" -eq 1 ] && flushed=1
    fi
    if [ "$flushed" = 0 ]; then
      cmd_out=$("$BB" timeout 5 cmd netd resolver flushnet "$active_id" 2>&1)
      cmd_rc=$?
      case "$cmd_out" in
        *'Command not recognized'*|*'Failure calling service'*|*'Failed transaction'*|*'Exception'*) cmd_ok=0 ;;
        *) [ "$cmd_rc" -eq 0 ] 2>/dev/null && cmd_ok=1 || cmd_ok=0 ;;
      esac
      [ "$cmd_ok" = 1 ] && flushed=1
    fi
  fi

  if [ "$flushed" -eq 1 ]; then
    # Mark successful rather than attempted operations. Leave other networks'
    # system resolver caches untouched. An entirely new outage can try once.
    printf '%s\n' "$outage_stamp" > "$DNSFLUSH_OUTAGE_FILE"
    printf '%s:%s\n' "$outage_stamp" "$active_id" > "$DNSFLUSH_SCOPE_FILE"
    log_msg "FCM guard: one bounded DNS cache flush for active_default_netid=$active_id binder=$binder_flushed outage=$outage_stamp; underlying DNS transport remains unproven"
  else
    log_msg "FCM guard: active default DNS cache flush unsupported/failed netid=$active_id; no success claimed"
  fi
}

# Local alpha23 follow-up: only after the first flush did not restore
# cellular DNS. One independent, evidence-gated retry per outage; never
# restart DNS/netd, change routes, add firewall rules or query on healthy FCM.
dns_late_native_recovery() {
  late_now=$1
  late_outage=$2
  [ "$late_outage" -ge 300 ] 2>/dev/null || return 1
  late_stamp=$(cat "$DOWN_FILE" 2>/dev/null)
  case "$late_stamp" in ''|*[!0-9]*) return 1;; esac
  [ "$(cat "$DNSFLUSH_OUTAGE_FILE" 2>/dev/null)" = "$late_stamp" ] || return 1
  late_repeat=0
  if [ "$(cat "$DNSLATE_FILE" 2>/dev/null)" = "$late_stamp" ]; then
    # A previous failed refresh must not permanently expire the eligibility
    # for the opt-in recovery when a call/awake screen blocked it.
    grep -Fxq 'FCM_CELLULAR_REBIND=1' "$RUNDIR/unified.conf" 2>/dev/null || return 1
    late_failed=${DNSLATE_FAILED_FILE:-$RUNDIR/fcm_dns_late_confirmed_failed.state}
    IFS=' ' read -r late_old_stamp late_old_id late_old_when < "$late_failed" || return 1
    case "$late_old_stamp:$late_old_id:$late_old_when" in *[!0-9:]*|:*|*::*|*:) return 1;; esac
    [ "$late_old_stamp" = "$late_stamp" ] || return 1
    [ $((late_now-late_old_when)) -ge 900 ] || return 1
    late_attempt="$RUNDIR/fcm_dns_late_reproof.epoch"
    late_previous=$(cat "$late_attempt" 2>/dev/null)
    case "$late_previous" in ''|*[!0-9]*) late_previous=0;; esac
    [ $((late_now-late_previous)) -ge 900 ] || return 1
    printf '%s\n' "$late_now" > "$late_attempt" || return 1
    late_repeat=1
  fi
  late_first=$(cat "$DNSFLUSH_FILE" 2>/dev/null)
  case "$late_first" in ''|*[!0-9]*) return 1;; esac
  [ $((late_now-late_first)) -ge 300 ] 2>/dev/null || return 1
  late_id=$(dns_active_default_netid) || return 1
  [ "$(cat "$DNSFLUSH_SCOPE_FILE" 2>/dev/null)" = "$late_stamp:$late_id" ] || return 1

  # Spend a bounded observation on this outage; a repeat only refreshes
  # evidence, never flushes again.
  [ "$late_repeat" = 0 ] || [ "$late_id" = "$late_old_id" ] || return 1
  if [ "$late_repeat" = 0 ]; then
    late_probe="$RUNDIR/fcm_dns_late_probe.state"
    late_probe_stamp=0; late_probe_when=0
    if [ -r "$late_probe" ]; then
      IFS=' ' read -r late_probe_stamp late_probe_when < "$late_probe" || return 1
    fi
    case "$late_probe_when" in ''|*[!0-9]*) return 1;; esac
    [ "$late_probe_stamp" != "$late_stamp" ] || [ $((late_now-late_probe_when)) -ge 900 ] || return 1
    printf '%s %s\n' "$late_stamp" "$late_now" > "$late_probe" || return 1
  fi
  late_diag=$(run_timeout dumpsys dnsresolver 2>/dev/null | awk -v id="$late_id" '
    /^NetId:/ { if (found) exit; if ($2 == id) found=1 }
    found { print }
  ')
  case "$late_diag" in '') return 1;; esac
  grep -q 'TransportType: CELLULAR' <<EOF || return 1
$late_diag
EOF
  grep -q 'Private DNS mode: OFF' <<EOF || return 1
$late_diag
EOF
  late_snapshot="$RUNDIR/dns-late-native.latest.txt"
  { date; printf 'outage=%s netid=%s\n' "$late_stamp" "$late_id"; cat <<EOF
$late_diag
EOF
  } > "$late_snapshot"
  late_servers=$(awk '
    /^  DNS servers:/ { collecting=1; next }
    collecting && /^    [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ / { print $1; next }
    collecting { exit }
  ' <<EOF | head -n 2
$late_diag
EOF
  )
  [ -n "$late_servers" ] || return 1

  # Probe the actual configured IPv4 resolver, not an unrelated public
  # nameserver. If Box capture exists, explicitly require its known direct
  # root/GID3005 exemption; otherwise skip rather than confuse capture
  # with physical DNS availability. No dependency on Box for other users.
  late_direct=0
  if iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL >/dev/null 2>&1; then
    late_rules=$(iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL 2>/dev/null) || return 1
    awk '
      /--uid-owner 0 --gid-owner 3005 -j RETURN/ { if (!mark) bypass=1 }
      /--dport 53.*MARK/ { mark=1 }
      END { exit !(bypass && mark) }
    ' <<EOF || return 1
$late_rules
EOF
    late_direct=1
  fi
  late_answer_ok=0
  for late_server in $late_servers; do
    # Only accept numerical dotted-quad addresses parsed from dnsresolver.
    case "$late_server" in *[!0-9.]*|''|.*|*.) continue;; esac
    if [ "$late_direct" = 1 ]; then
      late_answer=$("$BB" timeout -k 1 6 su -g 3005 0 -c "busybox timeout -k 1 4 busybox nslookup mtalk.google.com $late_server" 2>/dev/null || true)
    else
      late_answer=$("$BB" timeout -k 1 5 "$BB" nslookup mtalk.google.com "$late_server" 2>/dev/null || true)
    fi
    if printf '%s\n' "$late_answer" | awk '
      /^Name:[[:space:]]+mtalk\.google\.com\.?[[:space:]]*$/ { answer=1; next }
      answer && /^Address([[:space:]]+[0-9]+)?:/ {
        for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) found=1
      }
      END { exit !found }
    '; then
      late_answer_ok=1
      break
    fi
  done
  [ "$late_answer_ok" = 1 ] || {
    log_msg "FCM guard: late native DNS repair skipped: configured IPv4 server not proven reachable netid=$late_id"
    return 1
  }
  [ "$(cat "$DOWN_FILE" 2>/dev/null)" = "$late_stamp" ] || return 1
  [ "$(fcm_state)" = disconnected ] || return 1
  [ -z "$(android_resolve_mtalk 2>/dev/null)" ] || return 1
  [ "$(dns_active_default_netid)" = "$late_id" ] || return 1
  if [ "$late_repeat" = 1 ]; then
    printf '%s %s %s\n' "$late_stamp" "$late_id" "$late_now" > "$late_failed" || return 1
    log_msg "FCM guard: refreshed confirmed native DNS failure; opt-in recovery remains eligible netid=$late_id"
    return 1
  fi
  dnsresolver_binder_ready || return 1
  # Consume the flush only once the full evidence gates pass. Unsupported
  # or failed observations do not falsely claim a completed refresh.
  printf '%s\n' "$late_stamp" > "$DNSLATE_FILE" || return 1
  dnsresolver_binder_flush_one "$late_id" || return 1
  late_ip=$(android_resolve_mtalk 2>/dev/null || true)
  if [ -n "$late_ip" ]; then
    printf '%s\n' "$late_now" > "$DNSOK_FILE"
    log_msg "FCM guard: late native cache refresh verified GMS DNS recovered netid=$late_id server=$late_server mtalk=$late_ip"
    return 0
  fi
  log_msg "FCM guard: late native cache refresh netid=$late_id completed but GMS DNS still failed; no further flush during outage"
  printf '%s %s %s\n' "$late_stamp" "$late_id" "$late_now" > "${DNSLATE_FAILED_FILE:-$RUNDIR/fcm_dns_late_confirmed_failed.state}"
  return 1
}

# Hold a separate bounded lock only for the actual data transaction.
# The maintenance wakelock can have expired by the time DNS proof completes.
rb_wake_acquire() {
  rb_wake_tag="fcmu_dns_rebind_$$"
  [ -w /sys/power/wake_lock ] && [ -w /sys/power/wake_unlock ] || return 1
  printf '%s %s\n' "$rb_wake_tag" 180000000000 > /sys/power/wake_lock 2>/dev/null
}

rb_wake_release() {
  [ -n "$rb_wake_tag" ] || return 0
  printf '%s\n' "$rb_wake_tag" > /sys/power/wake_unlock 2>/dev/null || true
}

# Optional last resort. An Android cellular network recreation, unlike a
# DNS cache flush, rebuilds DNS transport/network state. Never enabled by
# default: it can briefly interrupt other cellular traffic. Only run on
# a fresh, independently proven native failure after both cache attempts.
dns_cellular_rebind_recovery() {
  grep -Fxq 'FCM_CELLULAR_REBIND=1' "$RUNDIR/unified.conf" 2>/dev/null || return 1
  rebind_now=$1; rebind_stamp=$2
  [ -r "$DNSLATE_FAILED_FILE" ] || return 1
  IFS=' ' read -r rb_stamp rb_id rb_when < "$DNSLATE_FAILED_FILE" || return 1
  case "$rb_stamp:$rb_id:$rb_when" in *[!0-9:]*|:*|*::*|*:) return 1;; esac
  [ "$rb_stamp" = "$rebind_stamp" ] || return 1
  [ "$rebind_now" -ge "$rb_when" ] && [ $((rebind_now-rb_when)) -le 120 ] || return 1
  # Only log a gate once per fresh proof/reason; no additional wakeups.
  rb_skip() {
    rb_gate="$rb_stamp:$rb_when:$1"
    rb_gate_file="$RUNDIR/fcm_dns_cellular_rebind.gate"
    if [ "$(cat "$rb_gate_file" 2>/dev/null)" != "$rb_gate" ]; then
      printf '%s\n' "$rb_gate" > "$rb_gate_file"
      log_msg "FCM guard: cellular recreation deferred netid=$rb_id gate=$1"
    fi
    return 1
  }
  # Some dual-SIM ROMs maintain mobile_data0/mobile_data1 and leave the
  # legacy unsuffixed global key at zero even when both slots are enabled.
  # Prefer the complete per-slot snapshot when available. Reject malformed
  # or duplicate keys, and never change asymmetric SIM preferences.
  rb_data_snapshot() {
    rb_settings=$(run_timeout settings list global 2>/dev/null) || return 1
    awk -F= '
      $1 ~ /^mobile_data[0-9]+$/ || $1 == "mobile_data" {
        if (NF != 2 || $2 !~ /^[01]$/ || seen[$1]++) { bad=1; next }
        if ($1 == "mobile_data") { global=$0; next }
        slots[++n]=$0
      }
      END {
        if (bad || (!n && global == "")) exit 1
        if (n) { for (i=1;i<=n;i++) print slots[i] } else print global
      }
    ' <<EOF | sort
$rb_settings
EOF
  }
  rb_poll_data() {
    rb_expected=$1
    rb_poll=0
    while [ "$rb_poll" -lt 5 ]; do
      [ "$(rb_data_snapshot)" = "$rb_expected" ] && return 0
      rb_poll=$((rb_poll+1))
      sleep 1
    done
    return 1
  }
  rb_active_sub() {
    rb_sub_dump=$(run_timeout dumpsys isub 2>/dev/null) || return 1
    awk -F= '
      /^[[:space:]]*defaultDataSubId=/ { if ($2 !~ /^[0-9]+$/ || d++) bad=1; else def=$2 }
      /^[[:space:]]*activeDataSubId=/ { if ($2 !~ /^[0-9]+$/ || a++) bad=1; else act=$2 }
      END { if (!bad && d==1 && a==1 && def==act) print def; else exit 1 }
    ' <<EOF
$rb_sub_dump
EOF
  }
  rb_attempt=$RUNDIR/fcm_dns_cellular_rebind.state
  rb_last_stamp=0; rb_last_time=0
  if [ -r "$rb_attempt" ]; then
    IFS=' ' read -r rb_last_stamp rb_last_time < "$rb_attempt" || return 1
  fi
  case "$rb_last_time" in ''|*[!0-9]*) return 1;; esac
  [ "$rb_last_stamp" != "$rebind_stamp" ] && [ $((rebind_now-rb_last_time)) -ge 21600 ] || { rb_skip cooldown; return 1; }
  rb_before=$(rb_data_snapshot)
  [ -n "$rb_before" ] || { rb_skip data-state-unavailable; return 1; }
  if printf '%s\n' "$rb_before" | grep -q '=0$'; then
    rb_skip data-disabled-or-asymmetric; return 1
  fi
  [ "$(settings get global private_dns_mode 2>/dev/null)" = off ] || { rb_skip private-dns; return 1; }
  run_timeout dumpsys power 2>/dev/null | grep -Eq '^[[:space:]]*mWakefulness=(Asleep|Dozing)$' || { rb_skip screen-or-power-state; return 1; }
  rb_calls=$(run_timeout dumpsys telephony.registry 2>/dev/null | grep -E '^[[:space:]]*mCallState=')
  [ -n "$rb_calls" ] && ! printf '%s\n' "$rb_calls" | grep -Evq '^[[:space:]]*mCallState=0$' || { rb_skip call-state; return 1; }
  run_timeout dumpsys audio 2>/dev/null | grep -Fxq -- '- Actual mode = MODE_NORMAL' || { rb_skip audio-mode; return 1; }
  run_timeout dumpsys tethering 2>/dev/null | grep -Eq '^[[:space:]]*Upstream wanted: false$' || { rb_skip tethering; return 1; }
  rb_connect=$(run_timeout dumpsys connectivity 2>/dev/null) || { rb_skip connectivity-unavailable; return 1; }
  # Android uses an external printf; dumpsys often exceeds Linux MAX_ARG_STRLEN
  # (observed 187778 bytes). Feed the snapshot via stdin, never argv. Otherwise
  # VPN detection fails open and the cellular/teardown gates misclassify it.
  rb_net_summary=$(awk -v id="$rb_id" '
    $1 == "Active" && $2 == "default" && $3 == "network:" { defaults++; def=$4 }
    /NetworkAgentInfo\{/ {
      if ($0 ~ /Transports: [^ ]*VPN([&|, ]|$)/) vpn=1
      if (index($0, "NetworkAgentInfo{network{" id "}")) {
        rows++
        if ($0 ~ /Transports: CELLULAR[[:space:]]+Capabilities: /) {
          cap=$0; sub(/^.*Transports: CELLULAR[[:space:]]+Capabilities: /, "", cap); sub(/[[:space:]].*$/, "", cap)
          if (cap ~ /(^|&)INTERNET(&|$)/) internet=1
        }
        if (match($0, /SubscriptionIds: \{[0-9]+\}/)) {
          sid=substr($0, RSTART, RLENGTH); sub(/^SubscriptionIds: \{/, "", sid); sub(/\}$/, "", sid)
        }
      }
    }
    END {
      if (vpn) print "vpn-or-unknown"
      else if (defaults != 1 || def != id) print "default-network-unverified"
      else if (rows != 1 || !internet) print "not-cellular-internet"
      else if (sid == "") print "subscription-unavailable"
      else print "ok " sid
    }
  ' <<EOF
$rb_connect
EOF
  ) || { rb_skip connectivity-parse-failed; return 1; }
  case "$rb_net_summary" in
    'ok '*) rb_net_sub=${rb_net_summary#ok };;
    vpn-or-unknown|default-network-unverified|not-cellular-internet|subscription-unavailable) rb_skip "$rb_net_summary"; return 1;;
    *) rb_skip connectivity-parse-failed; return 1;;
  esac
  rb_sub_before=$(rb_active_sub) || { rb_skip subscription-unavailable; return 1; }
  [ -n "$rb_net_sub" ] && [ "$rb_net_sub" = "$rb_sub_before" ] || { rb_skip subscription-mismatch; return 1; }
  [ "$(dns_active_default_netid)" = "$rb_id" ] || { rb_skip network-changed; return 1; }
  [ "$(cat "$DOWN_FILE" 2>/dev/null)" = "$rebind_stamp" ] || { rb_skip outage-changed; return 1; }
  [ "$(fcm_state)" = disconnected ] || { rb_skip fcm-not-disconnected; return 1; }
  [ -z "$(android_resolve_mtalk 2>/dev/null)" ] || { rb_skip dns-recovered; return 1; }
  # Prefer the supported phone shell interface. Do not fall through to a
  # different mutating command after an ambiguous Binder response.
  rb_backend=svc
  rb_help=$(run_timeout cmd phone data help 2>/dev/null || true)
  if printf '%s\n' "$rb_help" | grep -q 'data enable:' && printf '%s\n' "$rb_help" | grep -q 'data disable:'; then
    rb_backend=phone
  else
    command -v svc >/dev/null 2>&1 || { rb_skip no-data-control; return 1; }
  fi
  [ "$(rb_data_snapshot)" = "$rb_before" ] || { rb_skip data-state-changed; return 1; }
  [ "$(rb_active_sub)" = "$rb_sub_before" ] || { rb_skip subscription-changed; return 1; }
  [ "$(dns_active_default_netid)" = "$rb_id" ] || { rb_skip network-changed; return 1; }
  rb_off=$(printf '%s\n' "$rb_before" | sed 's/=1$/=0/')
  # Consume the attempt only after the scoped lock is held.
  (
    # Capture Binder output through a pipe (Android 17 may reject regular
    # file descriptors). A zero exit status does not prove a state change.
    rb_svc() {
      if [ "$rb_backend" = phone ]; then
        rb_output=$(run_timeout cmd phone data "$1" 2>&1) || return 1
      else
        rb_output=$(run_timeout svc data "$1" 2>&1) || return 1
      fi
      case "$rb_output" in *'Failure calling service'*|*'Failed transaction'*|*'Exception'*|*'Permission Denial'*) return 1;; esac
    }
    rb_wake_acquire || { rb_skip wakelock-unavailable; exit 1; }
    rb_mutating=0
    rb_restore() {
      if [ "$rb_mutating" = 1 ]; then
        if rb_svc enable && rb_poll_data "$rb_before"; then
          log_msg 'FCM guard: cellular recovery aborted; original data preferences restored'
        else
          log_msg 'FCM guard: cellular recovery aborted; data preference restoration NOT verified'
        fi
      fi
      rb_wake_release
    }
    trap rb_restore EXIT
    trap 'exit 1' HUP INT TERM
    printf '%s %s\n' "$rebind_stamp" "$rebind_now" > "$rb_attempt" || exit 1
    log_msg "FCM guard: opt-in cellular network recreation following confirmed DNS transport failure netid=$rb_id backend=$rb_backend"
    rb_mutating=1
    rb_svc disable || exit 1
    rb_poll_data "$rb_off" || exit 1
    # Wait for teardown, not merely for a settings write. Always restore
    # on failure; neither successful Binder status nor state alone proves
    # the cellular network has actually been recreated.
    rb_teardown=0
    while [ "$rb_teardown" -lt 5 ]; do
      rb_current=$(run_timeout dumpsys connectivity 2>/dev/null) || exit 1
      rb_teardown_state=$(awk -v id="$rb_id" '
        $1=="Active" && $2=="default" && $3=="network:" { defaults++; def=$4 }
        index($0,"NetworkAgentInfo{network{" id "}") { present=1 }
        END {
          if (present || def==id) print "present"
          else if (defaults==1 && (def ~ /^[0-9]+$/ || def=="none" || def=="null" || def=="-1")) print "absent"
          else print "unknown"
        }
      ' <<EOF
$rb_current
EOF
      ) || exit 1
      case "$rb_teardown_state" in absent) break;; present) :;; *) exit 1;; esac
      rb_teardown=$((rb_teardown+1))
      sleep 1
    done
    [ "$rb_teardown" -lt 5 ] || exit 1
    rb_svc enable || exit 1
    rb_poll_data "$rb_before" || exit 1
    [ "$(rb_active_sub)" = "$rb_sub_before" ] || exit 1
    trap - EXIT HUP INT TERM
    rb_wake_release
  ) || { log_msg 'FCM guard: cellular recreation command failed; no recovery claimed'; return 1; }
  log_msg 'FCM guard: original cellular network removed and data preferences restored; verify native DNS and FCM on next ordinary guard wake'
  return 0
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

# Last-resort GMS-only recycle must never act on a completely unvalidated
# network. Android's default NetId and its INTERNET+VALIDATED capability must
# refer to the SAME network, otherwise we leave Box/modem/Wi-Fi alone.
fcm_default_net_validated() {
  net_status=$(run_timeout dumpsys connectivity 2>/dev/null) || return 1
  active_net=$(printf '%s\n' "$net_status" | awk '
    $1=="Active" && $2=="default" && $3=="network:" &&
    $4 ~ /^[0-9]+$/ {print $4;exit}')
  case "$active_net" in ''|*[!0-9]*) return 1;; esac
  printf '%s\n' "$net_status" | awk -v id="$active_net" '
    index($0,"network{"id"}") && /Capabilities:/ &&
    /INTERNET/ && /VALIDATED/ {verified=1}
    END {exit !verified}'
}

# Polling and the event worker can wake at the same time. Serialize the whole
# guard so they cannot duplicate firewall rules or race restart accounting.
acquire_guard_lock || exit 0
trap 'release_guard_lock' EXIT HUP INT TERM

# alpha31: recover only our abandoned temporary resolver overlay.
if [ -r "$MODDIR/bin/fcm_dns_hosts_fallback.sh" ]; then
  . "$MODDIR/bin/fcm_dns_hosts_fallback.sh"
  fcm_hosts_recover_abandoned || { log_msg 'FCM guard: temporary resolver cleanup pending'; exit 0; }
fi

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
    # Ordinary healthy checks need one binder dump. Only a heartbeat can
    # change the state during this pass; keep its fresh read and recovery.
    [ "$KEEPALIVE_PROBED" = 0 ] || state=$(fcm_state)
    if [ "$state" = connected ]; then
      # Preserve an earlier outage if the service reports connected but the
      # actual endpoint is unavailable. Never reset the timer on that alone.
      if [ -f "$DOWN_FILE" ]; then
        current_endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
          | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
        if ! printf '%s\n' "$current_endpoint" | grep -Eq 'connected=[^[:space:]]+.*port=[0-9]+'; then
          # A prior confirmed outage still has no endpoint. Continue the
          # recovery path instead of silently returning on connected=true.
          state=disconnected
        fi
      fi
      if [ "$state" = connected ]; then
        rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$DNSOK_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
        exit 0
      fi
    fi
    [ "$state" = unknown ] && exit 0
    # With a prior outage and a missing endpoint, proceed just as with a
    # disconnected GcmService, subject to the existing DNS/TCP safeguards.
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
[ -n "$gpid" ] || exit 0

if [ ! -f "$DOWN_FILE" ]; then
  echo "$now" > "$DOWN_FILE"
  log_msg "FCM guard: GcmService disconnected; starting outage timer"
  exit 0
fi

down_since=$(cat "$DOWN_FILE" 2>/dev/null)
case "$down_since" in ''|*[!0-9]*) down_since=$now;; esac
outage=$((now-down_since))

# alpha11: UNKNOWN_HOST is evidence of a past lookup, not proof the
# resolver is STILL broken. Verify the CURRENT Android libc resolver first.
# The old early exit on every recent GMS event could indefinitely postpone
# recovery while repeated failed attempts refreshed the 15-minute window.
if [ "$outage" -ge 60 ] 2>/dev/null; then
  unknown_epoch=$(recent_gms_unknown_host_epoch 2>/dev/null || true)
  android_ip=$(android_resolve_mtalk 2>/dev/null || true)
  if [ -z "$android_ip" ]; then
    # Never restart GMS during a confirmed current resolver failure.
    rm -f "$DNSOK_FILE" 2>/dev/null || true
    remember_dns_failure "$now"
    flush_android_dns "$now"
    if dns_late_native_recovery "$now" "$outage"; then
      soft_reconnect_if_stalled "$now" "$outage" || true
      exit 0
    fi
    if command -v fcm_hosts_fallback >/dev/null 2>&1 &&
        fcm_hosts_fallback "$now" "$down_since" "$outage" "$unknown_epoch"; then
      exit 0
    fi
    if dns_cellular_rebind_recovery "$now" "$down_since"; then
      exit 0
    fi

    # alpha16: the current Box4Magisk profile routes FCM DNS over sing-box,
    # independently of the already-working GMS UID TCP 5228-5230 bypass.
    # On this phone its UDP resolver bound a removed cellular IP and returned
    # "network is unreachable" for mtalk.google.com even with a valid new
    # default route. Trigger only a bounded, evidence-gated Box recovery on
    # this CONFIRMED current GMS resolver failure; all normal/healthy FCM
    # checks have zero added work. Unknown Box/other phones skip safely.
    if [ -r "$MODDIR/bin/fcm_dns_box_repair.sh" ]; then
      repaired=$("$BB" timeout 85 /system/bin/sh "$MODDIR/bin/fcm_dns_box_repair.sh" repair 2>/dev/null || true)
      if [ "$repaired" = BOX_FCM_DNS_RECOVERY_TRIGGERED ]; then
        # Let the Box recovery settle before any further GMS intervention.
        ensure_fcm_uid_bypass
        exit 0
      elif [ "$outage" -ge 900 ] 2>/dev/null; then
        # alpha18: independent, read-only flight recorder BEFORE the fallback
        # makes a decision. It persists the exact failing gate (route, UID,
        # Box capture, root upstream DNS, etc.) once per 15 minutes. Unlike
        # alpha17 it records evidence even when a precondition fails before
        # the recovery state directory is created. No extra workers/alarms.
        if [ -r "$MODDIR/bin/fcm_dns_differential_diag.sh" ]; then
          "$BB" timeout 40 /system/bin/sh "$MODDIR/bin/fcm_dns_differential_diag.sh" \
            "$down_since" >/dev/null 2>&1 || true
        fi
        # alpha17: alpha16's exact stale-source log is often absent in a
        # background failure, leaving hours of repeated UNKNOWN_HOST.
        # Independent gates inside this helper demand: CURRENT GMS resolver
        # failure, raw upstream DNS success under root, actual Box DNS
        # interception and no manual Box disable. One recovery per outage,
        # 6-hour global floor, and at most one probe every 15 minutes.
        # Do not restart GMS or alter network settings on this path.
        fallback=$("$BB" timeout 105 /system/bin/sh \
          "$MODDIR/bin/fcm_dns_box_repair.sh" fallback "$down_since" 2>/dev/null || true)
        if [ "$fallback" = BOX_FCM_DNS_RECOVERY_TRIGGERED ]; then
          ensure_fcm_uid_bypass
          exit 0
        fi
      fi
    fi

    if [ -n "$unknown_epoch" ]; then
      unknown_age=$((now-unknown_epoch))
      rate_limited_dns_log "$now" "GMS UNKNOWN_HOST ${unknown_age}s ago AND current Android DNS unresolved; no GMS restart"
    else
      rate_limited_dns_log "$now" "Android resolver cannot resolve mtalk.google.com; no GMS restart"
    fi
    soft_reconnect_if_stalled "$now" "$outage" dns-failed || true
    # All scoped DNS and Box recovery paths have already had first refusal.
    # Do not permanently block every other recovery mode: after 30 minutes,
    # a strictly bounded GMS-only fallback may run on a VALIDATED network.
    [ "$outage" -ge 1800 ] 2>/dev/null || exit 0
  fi

  # Require two observations at least 90 seconds apart before permitting the
  # existing 5228-5230 path proof / rate-limited GMS fallback. Do not turn an
  # old UNKNOWN_HOST into a perpetually renewed DNS failure timestamp.
  if [ -n "$android_ip" ] && [ -f "$DNSFAIL_FILE" ]; then
    dns_ok_since=$(cat "$DNSOK_FILE" 2>/dev/null)
    case "$dns_ok_since" in ''|*[!0-9]*) dns_ok_since=0;; esac
    if [ "$dns_ok_since" -eq 0 ] 2>/dev/null || [ "$dns_ok_since" -gt "$now" ] 2>/dev/null; then
      dns_ok_since=$now
      printf '%s\n' "$now" > "$DNSOK_FILE"
      log_msg "FCM guard: alpha11 Android DNS recovered mtalk=$android_ip; stability confirmation started"
    fi
    if [ $((now-dns_ok_since)) -lt 90 ] 2>/dev/null; then
      soft_reconnect_if_stalled "$now" "$outage" || true
      exit 0
    fi
    rm -f "$DNSFAIL_FILE" "$DNSOK_FILE" 2>/dev/null || true
    log_msg "FCM guard: alpha11 DNS recovery stable 90s; enabling normal MCS path checks"
  fi
  if [ -n "$unknown_epoch" ]; then
    unknown_age=$((now-unknown_epoch))
    rate_limited_dns_log "$now" "Recent GMS UNKNOWN_HOST ${unknown_age}s ago but current Android DNS resolves mtalk=$android_ip; allowing guarded recovery"
  fi
fi

# A healthy resolver is not enough if GMS lost its own reconnect alarm. Repair
# that scheduler state before considering a process restart. The live incident
# on 2026-09-05 recovered in seconds from this broadcast with the same GMS PID.
if soft_reconnect_if_stalled "$now" "$outage"; then
  exit 0
fi

# Do not restart GMS in the same guard pass that just delivered the
# low-impact GCM_RECONNECT intent. Give native MCS at least 120 seconds.
recent_soft=$(cat "$SOFT_RECONNECT_FILE" 2>/dev/null)
case "$recent_soft" in ''|*[!0-9]*) recent_soft=0;; esac
if [ "$recent_soft" -gt 0 ] && [ $((now-recent_soft)) -lt 120 ]; then
  exit 0
fi

# Give Google's own reconnect logic five minutes before intervention. The old
# 10m grace plus 30/60/120m retry schedule could turn one stuck MCS state into
# a multi-hour push outage.
[ "$outage" -ge 300 ] 2>/dev/null || exit 0

# Distinguish a stuck GMS/MCS client from a genuine FCM path outage. Restarting
# GMS cannot repair an unreachable network and would only waste battery.
path=$(fcm_path_ready 2>/dev/null || true)
verified_mcs=1
if [ -z "$path" ]; then
  verified_mcs=0
  rate_limited_path_log "$now"
  [ "$outage" -ge 1800 ] 2>/dev/null || exit 0
  fcm_default_net_validated || exit 0
  path="validated-network unverified 0"
else
  rm -f "$PATHLOG_FILE" 2>/dev/null || true
fi

attempts=$(cat "$ATTEMPT_FILE" 2>/dev/null)
case "$attempts" in ''|*[!0-9]*) attempts=0;; esac
# At most two GMS-only recycles per outage when the FCM destination is not
# actually reachable. Existing global 1h..12h restart cool-down still applies.
[ "$verified_mcs" = 1 ] || [ "$attempts" -lt 2 ] || exit 0
last=$(cat "$LAST_FILE" 2>/dev/null)
case "$last" in ''|*[!0-9]*) last=0;; esac

# Fast early recovery, progressively reducing churn. Persistent failures are
# capped at one intervention per hour instead of either hammering GMS or
# waiting two hours between attempts.
# alpha12: ten hard restarts overnight never established MCS; avoid storms.
# LAST_FILE is deliberately retained across successful reconnects to enforce
# the global one-hour floor even if a new outage starts soon afterward.
case "$attempts" in
  0|1) min_gap=3600 ;;
  2) min_gap=10800 ;;
  3) min_gap=21600 ;;
  *) min_gap=43200 ;;
esac
[ $((now-last)) -ge "$min_gap" ] 2>/dev/null || exit 0

resolver=${path%% *}
rest=${path#* }
ip=${rest%% *}
port=${rest##* }
android_ip=$(android_resolve_mtalk 2>/dev/null || true)
[ -n "$android_ip" ] || android_ip=primary-unavailable
if [ "$verified_mcs" = 1 ]; then
  log_msg "FCM guard: outage=${outage}s MCS UID path verified resolver=$resolver endpoint=$ip:$port primary_dns=$android_ip; restarting GMS-host pid=$gpid attempt=$((attempts+1))"
else
  log_msg "FCM guard: LAST-RESORT outage=${outage}s validated default network but MCS route unknown; GMS-host-only restart pid=$gpid attempt=$((attempts+1))"
fi
expected_uid=$(gms_uid_for_probe) || exit 0
actual_uid=$(awk '/^Uid:/{print $2;exit}' "/proc/$gpid/status" 2>/dev/null)
[ "$actual_uid" = "$expected_uid" ] || exit 0
echo "$now" > "$LAST_FILE"
echo $((attempts+1)) > "$ATTEMPT_FILE"
kill -TERM "$gpid" 2>/dev/null || exit 0
sleep 20

state2=$(fcm_state)
if [ "$state2" = "connected" ]; then
  newpid=$(pidof com.google.android.gms.persistent 2>/dev/null | awk '{print $1}')
  [ -n "$newpid" ] || newpid=$(pidof com.google.android.gms 2>/dev/null | awk '{print $1}')
  endpoint=$(run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null \
    | grep -m1 'connected=' | sed 's/^[[:space:]]*//' || true)
  if fcm_mcs_endpoint_socket_ready "$endpoint"; then
    rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$DNSOK_FILE" "$SOFT_RECONNECT_FILE" 2>/dev/null || true
    log_msg "FCM guard: recovered newpid=${newpid:-unknown} GMS-owned MCS socket verified $endpoint"
  else
    log_msg "FCM guard: restart yielded connected=true but no MCS endpoint; retry schedule retained"
  fi
else
  log_msg "FCM guard: restart issued but GcmService state=$state2; retry schedule retained"
fi

