#!/system/bin/sh
# Source from the serialized FCM guard only, after a fresh connected snapshot.
fcm_mcs_socket_tuple() {
  # ss fields on Android/Linux: Recv-Q Send-Q Local Peer ..., then uid/inode.
  # Accept exactly one candidate, never guess a PID, UID, inode, IP or port.
  awk -v ip="$1" -v port="$2" -v uid="$3" '
    {
      remote=$4; p=remote; sub(/^.*:/, "", p)
      sub(/:[^:]*$/, "", remote)
      sub(/^\[/, "", remote); sub(/\]$/, "", remote)
      sub(/^::ffff:/, "", remote)
      if (remote != ip || p != port) next
      su=""; ino=""; pid=""; fd=""
      for (i=5; i<=NF; i++) {
        if ($i ~ /^uid:[0-9]+$/) {su=$i; sub(/^uid:/, "", su)}
        if ($i ~ /^ino:[0-9]+$/) {ino=$i; sub(/^ino:/, "", ino)}
      }
      if (match($0, /pid=[0-9]+,fd=[0-9]+/)) {
        pair=substr($0,RSTART,RLENGTH); split(pair,a,",")
        pid=a[1]; sub(/^pid=/,"",pid); fd=a[2]; sub(/^fd=/,"",fd)
      }
      if (su == uid && ino != "" && pid != "" && fd != "") {
        count++; tuple=pid " " fd " " su " " ino
      }
    }
    END { if (count==1) print tuple }
  '
}

fcm_socket_keepalive() {
  sk_now=$1
  sk_state="$RUNDIR/fcm_socket_keepalive.state"
  sk_helper="$MODDIR/bin/fcmu_socket_keepalive"
  command -v ss >/dev/null 2>&1 || return 0
  sk_endpoint=$(cat "$RUNDIR/fcm-observed.endpoint" 2>/dev/null)
  # A hostname alone, ambiguous address, or a non-MCS endpoint is not proof.
  case "$sk_endpoint" in connected=mtalk.google.com/*,port=*|connected=alt[0-9]*-mtalk.google.com/*,port=*) ;; *) return 0;; esac
  sk_ip=${sk_endpoint#*/}
  sk_ip=${sk_ip%,port=*}
  sk_ip=${sk_ip#\[}; sk_ip=${sk_ip%\]}
  sk_ip=${sk_ip#::ffff:}
  case "$sk_ip" in ''|*[!0-9a-fA-F:.]*) return 0;; esac
  sk_port=${sk_endpoint##*,port=}
  case "$sk_port" in 5228|5229|5230) ;; *) return 0;; esac
  sk_uid=${gms_uid:-}
  case "$sk_uid" in ''|*[!0-9]*)
    sk_uid=$(run_timeout pm list packages -U com.google.android.gms 2>/dev/null \
      | awk '$1=="package:com.google.android.gms" {sub(/^uid:/,"",$2); print $2; exit}')
    ;;
  esac
  case "$sk_uid" in ''|*[!0-9]*) return 0;; esac
  sk_tuple=$(run_timeout ss -Htnpe state established "( dport = :$sk_port )" 2>/dev/null \
      | fcm_mcs_socket_tuple "$sk_ip" "$sk_port" "$sk_uid")
  [ -n "$sk_tuple" ] || return 0
  sk_previous=; sk_last=; sk_result=
  [ ! -r "$sk_state" ] || read -r sk_previous sk_last sk_result < "$sk_state" || true
  set -- $sk_tuple
  [ "$#" -eq 4 ] || return 0
  sk_key="$1:$2:$3:$4"
  case "$sk_last" in ''|*[!0-9]*) sk_last=0;; esac
  # Check a replacement connection immediately; reverify same socket every
  # ten minutes without resetting the kernel timer or creating another timer.
  if [ "$sk_key" = "$sk_previous" ] && [ "$sk_now" -ge "$sk_last" ] \
      && [ $((sk_now-sk_last)) -lt 600 ]; then
    return 0
  fi
  if sk_out=$(run_timeout "$sk_helper" apply "$@" "$sk_ip" "$sk_port" 2>&1); then
    printf '%s %s ok\n' "$sk_key" "$sk_now" > "$sk_state"
    if [ "$sk_key" != "$sk_previous" ] || [ "$sk_result" != ok ]; then
      log_msg "FCM guard: scoped MCS TCP keepalive verified inode=$4 (idle<=180s, interval<=30s, probes<=4)"
    fi
  else
    printf '%s %s unsupported\n' "$sk_key" "$sk_now" > "$sk_state"
    if [ "$sk_result" != unsupported ]; then
      log_msg "FCM guard: MCS socket option unavailable; retain native GMS behavior (no health warning)"
    fi
  fi
}
