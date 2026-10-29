#!/system/bin/sh
MODDIR=${0%/*}/..
MODDIR=$(cd "$MODDIR" && pwd)
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
. "$MODDIR/bin/static_common.sh"
. "$MODDIR/bin/runtime_workers.sh"
mkdir -p "$RUNDIR"
OUT=$RUNDIR/.health.$$
level=0
emit() {
  case "$1" in GREEN) dot='🟢';; YELLOW) dot='🟡';; RED) dot='🔴';; *) dot='⚪';; esac
  printf '%s %s\t%s\t%s\n' "$dot" "$1" "$2" "$3" >> "$OUT"
  case "$1" in RED) level=2;; YELLOW) [ "$level" -ge 1 ] || level=1;; esac
}
: > "$OUT"
core_ok=1
for worker_name in settings maintenance events; do
  if read -r worker_pid worker_start 2>/dev/null < "$RUNDIR/$worker_name.pid" &&
      [ -n "$worker_start" ] && [ "$(worker_ticks "$worker_pid")" = "$worker_start" ]; then :;
  else core_ok=0; fi
done
if [ "$core_ok" = 1 ]; then emit GREEN CORE "three guard workers running"; else
  emit RED CORE "guard worker missing or legacy conflict; see startup-status.txt"
fi
observed=unknown stamp=0
read -r observed stamp 2>/dev/null < "$RUNDIR/fcm-observed.state" || true
now=$(date +%s)
case "$stamp" in ''|*[!0-9]*) stamp=0;; esac
if [ "${1:-}" = --fresh ]; then
  BB=/data/adb/magisk/busybox
  if [ -x "$BB" ]; then
    line=$("$BB" timeout 5 dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -m1 'Is client connected:' || true)
  else
    line=$(timeout 5 dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -m1 'Is client connected:' || true)
  fi
  case "$line" in *true*) observed=connected;; *false*) observed=disconnected;; *) observed=unknown;; esac
  stamp=$now
  printf '%s %s\n' "$observed" "$stamp" > "$RUNDIR/fcm-observed.state"
fi
[ $((now-stamp)) -le 300 ] 2>/dev/null || observed=unknown
case "$observed" in
 connected) emit GREEN FCM "GcmService reports connected; real message delivery remains unverified";;
 disconnected) emit RED FCM "connection disconnected; may be network/GMS; recovery core remains running";;
 *) emit YELLOW FCM "connection diagnostics unavailable or stale";;
esac
probe5() {
  if [ -x /data/adb/magisk/busybox ]; then /data/adb/magisk/busybox timeout 5 "$@";
  else timeout 5 "$@"; fi
}
greeze=$(probe5 dumpsys greezer 2>/dev/null | grep -m1 'mGmsLimitEnabled' || true)
case "$greeze" in
 *false*) emit GREEN GMS_LIMIT "OEM GMS limiter disabled";;
 *true*) emit YELLOW GMS_LIMIT "OEM GMS limiter still enabled";;
 *) emit GRAY GMS_LIMIT "OEM limiter interface absent/unavailable; other functions remain independent";;
esac
whitelist=$(probe5 settings --user 0 get system MILLET_NO_RESTRICT_APP </dev/null 2>/dev/null)
if [ -n "$greeze" ]; then
  case ",$whitelist," in *com.google.android.gms*) emit GREEN MILLET "GMS is in the no-restrict setting";;
    *) emit YELLOW MILLET "GMS no-restrict entry missing or SettingsProvider unavailable";; esac
else emit GRAY MILLET "OEM freezing interface absent/unavailable"; fi
idle=$(probe5 cmd deviceidle whitelist </dev/null 2>/dev/null)
if printf '%s\n' "$idle" | grep -Eq '^(system|user),com[.]google[.]android[.]gms,'; then
  emit GREEN DEVICEIDLE "native GMS exemption present"
else emit YELLOW DEVICEIDLE "native GMS exemption missing/unavailable"; fi
phase=DETECT detail="capability detection pending"
if [ -f "$MODDIR/backend/state" ]; then
  IFS="$(printf '\t')" read -r phase detail < "$MODDIR/backend/state" || true
fi
case "$phase" in
 ACTIVE) emit GREEN BACKEND "$detail";;
 ERROR|QUARANTINED) emit RED BACKEND "$detail";;
 *) emit YELLOW BACKEND "$detail";;
esac
mounted=0 capfile=
if cache_load; then
  capfile=$CACHE_DIR/capabilities.tsv
  cache_payload_ok && cache_security_ok && cache_mounted && mounted=1
fi
[ -n "$capfile" ] || capfile=$MODDIR/backend/last-capabilities.tsv
ready=0 total=0
if [ -r "$capfile" ]; then
  while IFS="$(printf '\t')" read -r feature state reason; do
    [ -n "$feature" ] || continue
    total=$((total+1))
    if [ "$state" = ready ] && [ "$mounted" = 1 ]; then
      ready=$((ready+1)); emit GREEN "$feature" "adapted backend is mounted"
    elif [ "$state" = ready ]; then
      emit YELLOW "$feature" "generated; next normal reboot required"
    else emit YELLOW "$feature" "$reason"; fi
  done < "$capfile"
else emit YELLOW FEATURES "static feature report not available; base core remains independent"; fi
case "$level" in
 0) lamp='🟢'; label='运行检查正常';;
 1) lamp='🟡'; label='部分功能/适配中';;
 *) lamp='🔴'; label='检测到问题';;
esac
case "$phase" in
 ACTIVE) phase_label='框架已加载';; READY) phase_label='待重启生效';; BUILDING) phase_label='自动适配中';;
 CORE_ONLY) phase_label='基础模式';; QUARANTINED) phase_label='框架需检查';; ERROR) phase_label='适配异常';;
 *) phase_label='等待自动适配';;
esac
case "$observed" in connected) fcm_label='在线';; disconnected) fcm_label='断开';; *) fcm_label='未知';; esac
summary="$lamp $label | FCM$fcm_label | 框架$ready/$total | $phase_label"
printf '%s\n' "$summary" > "$RUNDIR/health-summary.txt"
printf '%s\n' "Checked: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUT"
printf '%s\n' 'Green indicates current checks only; it does not prove end-to-end message delivery.' >> "$OUT"
mv -f "$OUT" "$RUNDIR/health-status.txt"
if [ -r "$MODDIR/module.prop" ] && ! grep -Fqx "description=$summary" "$MODDIR/module.prop"; then
  sed '/^description=/d;/^name=/d' "$MODDIR/module.prop" > "$MODDIR/.module.prop.$$"
  printf 'name=HyperOS FCM Unified Guard %s\ndescription=%s\n' "$lamp" "$summary" >> "$MODDIR/.module.prop.$$"
  chmod 644 "$MODDIR/.module.prop.$$"
  mv -f "$MODDIR/.module.prop.$$" "$MODDIR/module.prop"
fi
cat "$RUNDIR/health-summary.txt"
cat "$RUNDIR/health-status.txt"
