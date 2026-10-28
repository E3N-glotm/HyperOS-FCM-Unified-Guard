#!/system/bin/sh
MODE=${1:-status}

find_base() {
  for p in /data_mirror/data_ce/null/0/com.tencent.mm /data/user/0/com.tencent.mm /data/data/com.tencent.mm; do
    [ -d "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

fingerprint() {
  base=$1
  f="$base/shared_prefs/com.google.android.gms.appid.xml"
  [ -f "$f" ] || return 1
  token=$(sed -n 's#.*name="|T|[^"]*">\([^<]*\)</string>.*#\1#p' "$f" | head -n 1)
  [ -n "$token" ] || return 1
  printf '%s' "$token" | sha256sum | awk '{print substr($1,1,16)}'
}

clean_residue() {
  rm -rf /data/adb/fcm_unified_guard/backups/wechat_fcm_refresh_* /data/local/tmp/wechat_fcm_refresh_* 2>/dev/null || true
}

status() {
  base=$(find_base 2>/dev/null || true)
  echo "base=$base"
  if [ -n "$base" ]; then
    fp=$(fingerprint "$base" 2>/dev/null || true)
    echo "token_fp=$fp"
  fi
  version=$(dumpsys package com.tencent.mm 2>/dev/null | sed -n 's/.*versionName=//p' | head -n 1)
  echo "wechat_version=$version"
  push_pid=$(pidof com.tencent.mm:push 2>/dev/null | awk '{print $1}')
  echo "push_pid=$push_pid"
  if cmd package query-services --brief -a com.google.firebase.INSTANCE_ID_EVENT com.tencent.mm 2>/dev/null | grep -q 'FCMInstanceIDListenerService'; then
    echo "fcm_listener=registered"
  else
    echo "fcm_listener=missing"
  fi
  dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null |
    grep -E 'connected=|Is client connected:|Reconnect Scheduler Alarm:' | head -n 3 |
    sed 's/^[[:space:]]*/gms=/'
  logcat -b events -d -v time -t 120 2>/dev/null | grep 'c2dm' | tail -n 4 | sed 's/^/c2dm=/'
}

case "$MODE" in
  refresh)
    base=$(find_base) || { echo "error=no_wechat_data"; exit 2; }
    old=$(fingerprint "$base" 2>/dev/null || true)
    clean_residue
    am force-stop com.tencent.mm
    sleep 1
    rm -f "$base/shared_prefs/com.google.android.gms.appid.xml"           "$base/no_backup/com.google.InstanceId.properties"           "$base/no_backup/com.google.android.gms.appid-no-backup"
    am start -W -n com.tencent.mm/.ui.LauncherUI >/dev/null 2>&1 ||
      monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    echo "old_fp=$old"
    echo "base=$base"
    ;;
  clean)
    clean_residue
    echo "cleaned=1"
    ;;
  status)
    status
    ;;
  fingerprint)
    base=$(find_base) || exit 2
    fingerprint "$base"
    ;;
  *)
    echo "error=unknown_mode"
    exit 64
    ;;
esac
