#!/system/bin/sh
# Scoped last-resort recovery; never edit the original hosts file.
fcm_hosts_ipv4() {
  awk '{n=split($0,a,"."); if(n!=4) next
     ok=1; for(i=1;i<=4;i++) if(a[i]!~/^(0|[1-9][0-9]*)$/ || a[i]>255) ok=0
     if(ok && a[1]>0 && a[1]<224 && a[1]!=10 && a[1]!=127 &&
        !(a[1]==169 && a[2]==254) && !(a[1]==172 && a[2]>=16 && a[2]<=31) &&
        !(a[1]==192 && a[2]==168) && !(a[1]==100 && a[2]>=64 && a[2]<=127)) print}'
}

fcm_hosts_dns_answers() {
  awk '/^Name:[[:space:]]+mtalk\.google\.com\.?[[:space:]]*$/ {answer=1;next}
       /^Name:/ {answer=0;next}
       answer && /^Address([[:space:]]+[0-9]+)?:/ {
         for(i=2;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i
       }' | fcm_hosts_ipv4 | awk '!seen[$0]++'
}

fcm_hosts_netd_pid() {
  hp=$(pidof netd 2>/dev/null)
  case "$hp" in ''|*[!0-9]*) return 1;; esac
  [ "$(cat "/proc/$hp/comm" 2>/dev/null)" = netd ] ||
    [ "$(readlink "/proc/$hp/exe" 2>/dev/null)" = /system/bin/netd ] || return 1
  printf '%s\n' "$hp"
}

fcm_hosts_overlay_path() { printf '%s/fcmu_dns_hosts.overlay\n' "$RUNDIR"; }

fcm_hosts_own_top() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  hsrc=$("$BB" stat -c '%d:%i' "$1" 2>/dev/null) || return 1
  hdst=$("$BB" stat -c '%d:%i' /system/etc/hosts 2>/dev/null) || return 1
  [ -n "$hsrc" ] && [ "$hsrc" = "$hdst" ]
}

fcm_hosts_cleanup_local() {
  hoverlay=$(fcm_hosts_overlay_path)
  [ -f "$hoverlay" ] && [ ! -L "$hoverlay" ] || return 0
  if fcm_hosts_own_top "$hoverlay"; then
    "$BB" umount /system/etc/hosts || return 1
  fi
  # Never remove another module's mount or destroy our source while mounted.
  awk '$5=="/system/etc/hosts" && $4 ~ /\/fcmu_dns_hosts\.overlay$/ {found=1}
       END {exit !found}' /proc/self/mountinfo && return 1
  rm -f "$hoverlay"
}

fcm_hosts_recover_abandoned() {
  [ -f "$(fcm_hosts_overlay_path)" ] || return 0
  hpid=$(fcm_hosts_netd_pid) || return 1
  "$BB" timeout -k 1 5 "$BB" nsenter -t "$hpid" -m /system/bin/sh \
    "$MODDIR/bin/fcm_dns_hosts_fallback.sh" --fcmu-hosts-cleanup
}

fcm_hosts_tls_ready() {
  h_tls_ip=$1; h_tls_uid=$2
  [ -x /system/bin/curl ] || return 1
  case "$h_tls_ip" in ''|*[!0-9.]*) return 1;; esac
  case "$h_tls_uid" in ''|*[!0-9]*) return 1;; esac
  h_tls_log=$("$BB" timeout -k 1 8 su -s /system/bin/sh "$h_tls_uid" -c \
    "/system/bin/curl --noproxy '*' -v --head --connect-timeout 4 --max-time 6 --resolve mtalk.google.com:5228:$h_tls_ip https://mtalk.google.com:5228/ -o /dev/null" 2>&1 || true)
  printf '%s\n' "$h_tls_log" | grep -Fq 'SSL certificate verify ok.' &&
    printf '%s\n' "$h_tls_log" | grep -Fq 'host "mtalk.google.com" matched cert'
}

fcm_hosts_network_safe() {
  awk -v id="$1" '
    $1=="Active" && $2=="default" && $3=="network:" && $4==id {active=1}
    /^[[:space:]]*NetworkAgentInfo\{/ {
      if(index($0,"network{"id"}")) physical=1
      t=$0; sub(/^.*Transports:[[:space:]]*/,"",t); sub(/[[:space:]]+Capabilities:.*/,"",t)
      if(t ~ /(^|[ &])VPN([ &\]]|$)/ || $0 ~ /ni\{VPN[[:space:]]/) vpn=1
    }
    END {exit !(active && physical && !vpn)}'
}

fcm_hosts_dns_servers() {
  awk -v id="$1" '
    /^NetId:/ {if(found) exit; if($2==id) found=1}
    found && /TransportType: CELLULAR/ {cell=1}
    found && /Private DNS mode: OFF/ {off=1}
    found && /^  DNS servers:/ {dns=1;next}
    found && dns && /^    [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ / {if(n<2) a[++n]=$1;next}
    found && dns && /^    / {next}
    found && dns {dns=0}
    END {if(cell && off) for(i=1;i<=n;i++) print a[i]}'
}

fcm_hosts_connection_verified() {
  [ "$(fcm_state)" = connected ] || return 1
  h_ep=$(cat "$RUNDIR/fcm-observed.endpoint" 2>/dev/null)
  case "$h_ep" in connected=mtalk.google.com/*,port=*|connected=alt[0-9]*-mtalk.google.com/*,port=*) ;; *) return 1;; esac
  h_peer=$(printf '%s\n' "$h_ep" | sed 's@^[^/]*/@@;s/,port=.*//;s/^\[//;s/\]$//;s/^::ffff://')
  h_port=$(printf '%s\n' "$h_ep" | sed 's/^.*,port=//')
  case "$h_port" in 5228|5229|5230) ;; *) return 1;; esac
  [ -r "$MODDIR/bin/fcm_socket_keepalive.sh" ] || return 1
  . "$MODDIR/bin/fcm_socket_keepalive.sh"
  [ -n "$(run_timeout ss -Htnpe state established "( dport = :$h_port )" 2>/dev/null | fcm_mcs_socket_tuple "$h_peer" "$h_port" "$1")" ]
}

fcm_hosts_transaction() (
  h_ip=$1; h_uid=$2; h_net=$3
  [ "$(printf '%s\n' "$h_ip" | fcm_hosts_ipv4)" = "$h_ip" ] || exit 1
  case "$h_uid:$h_net" in *[!0-9:]*|:*|*:) exit 1;; esac
  hoverlay=$(fcm_hosts_overlay_path)
  [ ! -e "$hoverlay" ] && [ ! -L "$hoverlay" ] || exit 1
  run_timeout dumpsys connectivity 2>/dev/null | fcm_hosts_network_safe "$h_net" || exit 1
  [ -n "$(run_timeout dumpsys dnsresolver 2>/dev/null | fcm_hosts_dns_servers "$h_net")" ] || exit 1
  run_timeout dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null |
    grep -q 'Is client connected: false' || exit 1
  [ -f /system/etc/hosts ] && [ ! -L /system/etc/hosts ] || exit 1
  awk '{sub(/#.*/,""); for(i=2;i<=NF;i++){n=tolower($i);sub(/\.$/,"",n);if(n=="mtalk.google.com") found=1}} END{exit !found}' \
    /system/etc/hosts && exit 1
  [ "$("$BB" stat -c %s /system/etc/hosts)" -le 1048576 ] || exit 1
  trap 'fcm_hosts_cleanup_local' EXIT
  trap 'exit 1' HUP INT TERM
  umask 077
  (set -C; cat /system/etc/hosts > "$hoverlay") || exit 1
  printf '\n%s mtalk.google.com\n' "$h_ip" >> "$hoverlay" || exit 1
  chmod 644 "$hoverlay" || exit 1
  chcon u:object_r:system_file:s0 "$hoverlay" || exit 1
  "$BB" mount --bind "$hoverlay" /system/etc/hosts || exit 1
  fcm_hosts_own_top "$hoverlay" || exit 1
  (trap '' HUP; sleep 35; fcm_hosts_cleanup_local) </dev/null >/dev/null 2>&1 &
  h_lookup=$("$BB" timeout -k 1 5 su -s /system/bin/sh "$h_uid" -c \
    '/system/bin/ping -c 1 -W 1 mtalk.google.com' 2>&1 || true)
  printf '%s\n' "$h_lookup" | awk -v ip="$h_ip" '$1=="PING" && index($0,"("ip")"){found=1} END{exit !found}' || exit 1
  "$BB" timeout -k 1 8 am broadcast --user 0 \
    -a com.google.android.intent.action.GCM_RECONNECT -p com.google.android.gms >/dev/null 2>&1 || exit 1
  sleep 10
  exit 0
)

fcm_hosts_fallback() {
  hnow=$1; hstamp=$2; houtage=$3; hunknown=$4
  [ "$houtage" -ge 300 ] && [ -n "$hunknown" ] || return 1
  grep -Fxq 'FCM_DNS_HOSTS_FALLBACK=0' "$RUNDIR/unified.conf" 2>/dev/null && return 1
  [ -x /system/bin/curl ] && command -v chcon >/dev/null 2>&1 || return 1
  [ ! -e "$(fcm_hosts_overlay_path)" ] || return 1
  hstate="$RUNDIR/fcm_dns_hosts_fallback.state"
  hprev=0; hlast=0; hcount=0
  [ ! -r "$hstate" ] || read -r hprev hlast hcount < "$hstate" || return 1
  case "$hprev:$hlast:$hcount" in *[!0-9:]*|:*|*::*|*:) return 1;; esac
  [ "$hnow" -ge "$hlast" ] && [ $((hnow-hlast)) -ge 900 ] || return 1
  [ "$hprev" = "$hstamp" ] || hcount=0
  [ "$hcount" -lt 3 ] || return 1
  hnet=$(dns_active_default_netid) || return 1
  run_timeout dumpsys connectivity 2>/dev/null | fcm_hosts_network_safe "$hnet" || return 1
  hservers=$(run_timeout dumpsys dnsresolver 2>/dev/null | fcm_hosts_dns_servers "$hnet")
  [ -n "$hservers" ] || return 1
  huid=$(gms_uid_for_probe) || return 1
  printf '%s %s %s\n' "$hstamp" "$hnow" "$((hcount+1))" > "$hstate" || return 1
  hbox=0
  if iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL >/dev/null 2>&1; then
    iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL 2>/dev/null |
      awk '/--uid-owner 0 --gid-owner 3005 -j RETURN/{if(!mark) bypass=1}
           /--dport 53.*MARK/{mark=1} END{exit !(bypass&&mark)}' || return 1
    hbox=1
  fi
  hcandidate=
  for hserver in $hservers; do
    case "$hserver" in ''|*[!0-9.]*) continue;; esac
    if [ "$hbox" = 1 ]; then
      hraw=$("$BB" timeout -k 1 6 su -g 3005 0 -c "busybox timeout -k 1 4 busybox nslookup mtalk.google.com $hserver" 2>/dev/null || true)
    else
      hraw=$("$BB" timeout -k 1 5 "$BB" nslookup mtalk.google.com "$hserver" 2>/dev/null || true)
    fi
    for haddr in $(printf '%s\n' "$hraw" | fcm_hosts_dns_answers | head -n 2); do
      if fcm_hosts_tls_ready "$haddr" "$huid"; then hcandidate=$haddr; break; fi
    done
    [ -z "$hcandidate" ] || break
  done
  [ -n "$hcandidate" ] || return 1
  [ "$(dns_active_default_netid)" = "$hnet" ] && [ "$(fcm_state)" = disconnected ] || return 1
  [ "$(cat "$DOWN_FILE" 2>/dev/null)" = "$hstamp" ] && [ -z "$(android_resolve_mtalk 2>/dev/null)" ] || return 1
  hpid=$(fcm_hosts_netd_pid) || return 1
  log_msg "FCM guard: native DNS still failed; temporary TLS-verified MCS resolver recovery netid=$hnet"
  "$BB" timeout -k 3 35 "$BB" nsenter -t "$hpid" -m /system/bin/sh \
    "$MODDIR/bin/fcm_dns_hosts_fallback.sh" --fcmu-hosts-transaction "$hcandidate" "$huid" "$hnet" || true
  fcm_hosts_recover_abandoned || { log_msg 'FCM guard: temporary resolver cleanup deferred; no recovery claimed'; return 1; }
  [ ! -e "$(fcm_hosts_overlay_path)" ] || return 1
  if fcm_hosts_connection_verified "$huid"; then
    log_msg "FCM guard: temporary resolver removed; native MCS reconnect verified netid=$hnet"
    rm -f "$DOWN_FILE" "$ATTEMPT_FILE" "$PATHLOG_FILE" "$DNSLOG_FILE" "$DNSFAIL_FILE" "$DNSOK_FILE" "$SOFT_RECONNECT_FILE"
    return 0
  fi
  log_msg 'FCM guard: temporary resolver removed; MCS recovery not confirmed'
  return 1
}

case "${1:-}" in
  --fcmu-hosts-cleanup|--fcmu-hosts-transaction)
    MODDIR=$(dirname "$0")/..
    . "$MODDIR/bin/lib.sh"
    if [ "$1" = --fcmu-hosts-cleanup ]; then fcm_hosts_cleanup_local; exit $?; fi
    shift
    fcm_hosts_transaction "$@"
    exit $?
    ;;
esac
