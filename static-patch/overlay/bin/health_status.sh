#!/system/bin/sh
MODDIR=${0%/*}/..
MODDIR=$(cd "$MODDIR" && pwd)
RUNDIR=${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}
. "$MODDIR/bin/static_common.sh"
. "$MODDIR/bin/runtime_workers.sh"
backend_read_state
[ "$phase" != CHECKING ] || backend_publish_status CHECKING
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
# Guard poll (120s) and Magisk status refresh (300s) run independently.
# The status refresh may land immediately BEFORE the next successful FCM
# observation and publish "FCM unknown" for five more minutes. If the cached
# observation is stale/unknown, make one bounded direct probe during this
# existing status refresh. Normal (fresh) cache adds zero dumpsys calls.
# The guard alone owns fcm-observed.state: do not clobber an observation from
# the concurrent guard poll with a failed/slow UI probe.
observed=unknown stamp=0
read -r observed stamp 2>/dev/null < "$RUNDIR/fcm-observed.state" || true
now=$(date +%s)
case "$stamp" in ''|*[!0-9]*) stamp=0;; esac
need_probe=0
case "$observed" in connected|disconnected) :;; *) need_probe=1;; esac
if [ "$stamp" -eq 0 ] || [ "$stamp" -gt "$now" ] || [ $((now-stamp)) -gt 300 ]; then
  observed=unknown
  need_probe=1
fi
[ "${1:-}" != --fresh ] || need_probe=1
if [ "$need_probe" = 1 ]; then
  BB=/data/adb/magisk/busybox
  if [ -x "$BB" ]; then
    line=$("$BB" timeout 5 dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -m1 'Is client connected:' || true)
  else
    line=$(timeout 5 dumpsys activity service com.google.android.gms/.gcm.GcmService 2>/dev/null | grep -m1 'Is client connected:' || true)
  fi
  case "$line" in
    *"Is client connected: true"*) observed=connected;;
    *"Is client connected: false"*) observed=disconnected;;
    *) observed=unknown;;
  esac
fi
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
# Greeze dumpsys and SettingsProvider are independent interfaces.
whitelist=$(probe5 settings --user 0 get system MILLET_NO_RESTRICT_APP </dev/null 2>/dev/null)
case "$whitelist" in
  ''|null|*'Failed transaction'*|*'Failure calling service settings'*|*'Exception'*)
    emit GRAY MILLET "no-restrict setting absent/unavailable; Greeze diagnostics independent";;
  *)
    if printf '%s\n' "$whitelist" | tr ',' '\n' | grep -Eq '^[[:space:]]*com[.]google[.]android[.]gms[[:space:]]*$'; then
      emit GREEN MILLET "GMS is in the no-restrict setting"
    else
      emit YELLOW MILLET "GMS no-restrict entry not present"
    fi;;
esac
# The static backend currently patches services.jar + miui-services.jar only.
# PowerKeeper APK-local GmsObserver/NetdExecutor/Doze-list hooks from the
# former LSPosed module are NOT equivalent and must not be hidden behind 10/10.
if [ -r "$MODDIR/backend/powerkeeper-capabilities.tsv" ]; then
  # APK existence, observer class, binder call-chain and equivalence marker
  # are metadata, NOT hookable method signatures. Do not count them as hooks.
  pk_present=$(awk -F '\t' '$1 ~ /^pk\./ && $1!="pk.apk" && $1!="pk.gms.observer" && $1!="pk.gms.binder_chain" && $1!="pk.equivalence" && $2=="present" {n++} END {print n+0}' "$MODDIR/backend/powerkeeper-capabilities.tsv")
  pk_variant=$(awk -F '\t' '$1 ~ /^pk\./ && $1!="pk.apk" && $1!="pk.gms.observer" && $1!="pk.gms.binder_chain" && $1!="pk.equivalence" && $2=="variant" {n++} END {print n+0}' "$MODDIR/backend/powerkeeper-capabilities.tsv")
  pk_probe_label="$pk_present detected method signatures, $pk_variant variants"
else
  pk_probe_label="APK capabilities not yet scanned"
fi
# Zygisk mapping is proof of native loading, not of ART Hook installation,
# method execution, Greezer state or FCM message delivery.
if [ -f "$MODDIR/zygisk/arm64-v8a.so" ]; then
  if [ -f "$MODDIR/backend/powerkeeper-hook.disable" ]; then
    emit YELLOW POWERKEEPER "native runtime quarantined after unacknowledged boot; FCM guard remains enabled; $pk_probe_label"
  else
    pk_mapped=0
    pk_pid=
    if [ -r "$MODDIR/backend/powerkeeper-packages.list" ]; then
      while IFS= read -r pk_name; do
        case "$pk_name" in ''|*[!A-Za-z0-9_.$]*) continue;; esac
        pk_pid=$(pidof "$pk_name" 2>/dev/null | awk '{print $1}')
        [ -n "$pk_pid" ] || continue
        if grep -Fq '/fcm_unified_guard/zygisk/arm64-v8a.so' "/proc/$pk_pid/maps" 2>/dev/null; then
          pk_mapped=1
          break
        fi
      done < "$MODDIR/backend/powerkeeper-packages.list"
    fi
    if [ "$pk_mapped" = 1 ]; then
      emit YELLOW POWERKEEPER "native Zygisk library mapped; ART/OEM method coverage and delivery unverified; $pk_probe_label"
    else
      emit YELLOW POWERKEEPER "runtime bundled but OEM process injection not verified; check Zygisk / architecture; $pk_probe_label"
    fi
  fi
elif [ -r "$MODDIR/backend/powerkeeper-capabilities.tsv" ]; then
  emit GRAY POWERKEEPER "read-only APK probe: $pk_probe_label; 0 PowerKeeper runtime hooks enabled (static-only build)"
else
  emit GRAY POWERKEEPER "PowerKeeper runtime not included; optional interface discovery unavailable"
fi
idle=$(probe5 cmd deviceidle whitelist </dev/null 2>/dev/null)
if printf '%s\n' "$idle" | grep -Eq '^(system|user),com[.]google[.]android[.]gms,'; then
  emit GREEN DEVICEIDLE "native GMS exemption present"
else emit YELLOW DEVICEIDLE "native GMS exemption missing/unavailable"; fi
backend_read_state
mounted=0 capfile=
if cache_load; then
  capfile=$CACHE_DIR/capabilities.tsv
  cache_payload_ok && cache_security_ok && cache_mounted && mounted=1
fi
case "$phase:$mounted" in
 ACTIVE:0|MOUNTED:0) phase=ERROR; detail='framework payload not verified in this boot; inspect mount/cache diagnostics';;
esac
case "$phase" in
 ACTIVE) emit GREEN BACKEND "$detail";;
 ERROR|QUARANTINED) emit RED BACKEND "$detail";;
 *) emit YELLOW BACKEND "$detail";;
esac
[ -n "$capfile" ] || capfile=$MODDIR/backend/last-capabilities.tsv
ready=0 total=0
framework_label=未知
if [ -s "$capfile" ]; then
  while IFS="$(printf '\t')" read -r feature state reason; do
    [ -n "$feature" ] || continue
    total=$((total+1))
    if [ "$state" = ready ] && [ "$mounted" = 1 ]; then
      ready=$((ready+1)); emit GREEN "$feature" "adapted backend is mounted"
    elif [ "$state" = ready ] && [ "$phase" = READY ]; then
      emit YELLOW "$feature" "generated; next normal reboot required"
    elif [ "$state" = ready ]; then
      emit YELLOW "$feature" "cached; current-boot framework validation pending"
    else emit YELLOW "$feature" "$reason"; fi
  done < "$capfile"
  framework_label="$ready/$total"
else
  emit YELLOW FEATURES "feature report missing; check backend/state and backend/build.log; base core independent"
fi
case "$level" in
 0) lamp='🟢'; label='运行检查正常';;
 1) lamp='🟡'; label='部分功能/适配中';;
 *) lamp='🔴'; label='检测到问题';;
esac
phase_label=$(backend_phase_label "$phase")
case "$observed" in connected) fcm_label='在线';; disconnected) fcm_label='断开';; *) fcm_label='未知';; esac
summary="$lamp $label | FCM$fcm_label | 框架$framework_label | $phase_label"
printf '%s\n' "$summary" > "$RUNDIR/health-summary.txt"
printf '%s\n' "Checked: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUT"
printf '%s\n' 'Green indicates current checks only; it does not prove end-to-end message delivery.' >> "$OUT"
mv -f "$OUT" "$RUNDIR/health-status.txt"
module_status_write "$lamp" "$summary"
cat "$RUNDIR/health-summary.txt"
cat "$RUNDIR/health-status.txt"
