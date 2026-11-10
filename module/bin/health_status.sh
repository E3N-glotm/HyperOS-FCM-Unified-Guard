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
verified_count=0
unknown_count=0
emit() {
  case "$1" in GREEN) dot='🟢';; YELLOW) dot='🟡';; RED) dot='🔴';; *) dot='⚪';; esac
  printf '%s %s\t%s\t%s\n' "$dot" "$1" "$2" "$3" >> "$OUT"
  case "$1" in
    RED) level=2;;
    YELLOW) [ "$level" -ge 1 ] || level=1;;
    GREEN) verified_count=$((verified_count+1));;
    GRAY) unknown_count=$((unknown_count+1));;
  esac
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
# A kernel alarmtimer is an independent deep-suspend wake source, unlike
# userspace shell sleep. The most recent wake timestamp is evidence of actual
# timer completion, not proof of end-to-end message delivery.
if [ -x "$MODDIR/bin/fcmu_alarm_wait" ]; then
  wake_status=$(cat "$RUNDIR/alarm-wakeup.state" 2>/dev/null)
  case "$wake_status" in
    kernel-alarmtimer*) emit GREEN WAKEUP "ARM64 kernel wakeup alarm active: $wake_status" ;;
    fallback-sleep*) emit YELLOW WAKEUP "kernel alarm failed; using non-wakeup fallback: $wake_status" ;;
    *) emit GRAY WAKEUP "kernel alarm helper installed; first scheduled wake not observed yet" ;;
  esac
else
  emit GRAY WAKEUP "kernel alarm support not confirmed; no deep-suspend wake conclusion"
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
 *) emit GRAY FCM "connection diagnostics unavailable or stale; no disconnect proven";;
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
# Only a parseable package list is valid negative evidence. Missing, denied,
# error/help or unexpected OEM output does not establish a functional defect.
whitelist=$(probe5 settings --user 0 get system MILLET_NO_RESTRICT_APP </dev/null 2>/dev/null)
case "$whitelist" in
  ''|null|*'Failed transaction'*|*'Failure calling service settings'*|*'Exception'*|*'Permission denial'*|*'Error'*|*'error'*)
    emit GRAY MILLET "no-restrict setting unavailable or malformed; GMS absence unproven";;
  *)
    if printf '%s\n' "$whitelist" | tr ',' '\n' | grep -Eq '^[[:space:]]*com[.]google[.]android[.]gms[[:space:]]*$'; then
      emit GREEN MILLET "GMS is in the no-restrict setting"
    elif printf '%s\n' "$whitelist" | tr ',' '\n' | grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*){2,}[[:space:]]*$'; then
      emit YELLOW MILLET "GMS absent from an actual readable package list"
    else
      emit GRAY MILLET "unrecognized no-restrict setting response; no failure proven"
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
      emit GRAY POWERKEEPER "native Zygisk mapped; OEM hook coverage not yet verified; $pk_probe_label"
    else
      emit GRAY POWERKEEPER "runtime bundled; OEM process injection not yet verified; $pk_probe_label"
    fi
  fi
elif [ -r "$MODDIR/backend/powerkeeper-capabilities.tsv" ]; then
  emit GRAY POWERKEEPER "read-only APK probe: $pk_probe_label; 0 PowerKeeper runtime hooks enabled (static-only build)"
else
  emit GRAY POWERKEEPER "PowerKeeper runtime not included; optional interface discovery unavailable"
fi
# alpha15: app-private /data/user_de is visible in the OEM application's
# mount namespace but is intentionally NOT necessarily visible from a Magisk
# root-shell namespace. Read through /proc/<PID>/root to use the CURRENT
# PowerKeeper process's filesystem view. Never create/alter private directories.
# The file is tiny and this only adds one read to the existing status poll.
pk_runtime_audit=
if [ "${pk_mapped:-0}" = 1 ] && [ -n "${pk_pid:-}" ] && [ -n "${pk_name:-}" ]; then
  case "$pk_pid:$pk_name" in
    *[!A-Za-z0-9_.$:]*|:*|*:) ;;
    *) pk_runtime_audit="/proc/$pk_pid/root/data/user_de/0/$pk_name/files/fcmu_pk_runtime_alpha14.tsv" ;;
  esac
fi
pk_audit_fresh=0
if [ -n "$pk_runtime_audit" ] && [ -r "$pk_runtime_audit" ]; then
  read -r boot_uptime unused < /proc/uptime
  boot_uptime=${boot_uptime%%.*}
  case "$boot_uptime" in ''|*[!0-9]*) boot_uptime=0;; esac
  pk_boot_epoch=$((now-boot_uptime))
  pk_audit_modified=$(stat -c %Y "$pk_runtime_audit" 2>/dev/null || echo 0)
  case "$pk_audit_modified" in ''|*[!0-9]*) pk_audit_modified=0;; esac
  if [ "$pk_audit_modified" -gt "$pk_boot_epoch" ] && [ "$pk_audit_modified" -le "$now" ] &&
       grep -Fq "alpha14 attach_backup_completed pid=$pk_pid" "$pk_runtime_audit" 2>/dev/null; then
    # Boot timestamp AND exact running PID must match: old process evidence
    # cannot make a restarted/unhooked PowerKeeper look healthy.
    pk_audit_fresh=1
  fi
fi
if [ "$pk_audit_fresh" = 1 ]; then
  if grep -Fq 'hook pk.gms.updateFrameworkGmsNetStatus=hook_installed' "$pk_runtime_audit" 2>/dev/null &&
     grep -Fq 'hook pk.doze.whitelist=hook_installed' "$pk_runtime_audit" 2>/dev/null; then
    emit GREEN PK_METHODS "Verified PowerKeeper GmsObserver and Doze OEM ART hooks installed (message delivery not tested)"
  else
    emit GRAY PK_METHODS "GmsObserver/Doze OEM ART hooks not both confirmed installed; failure not established"
  fi
  if grep -Fq 'hook pk.firewall.gmsDnsUidRule=hook_installed' "$pk_runtime_audit" 2>/dev/null; then
    pk_dns_result=$(grep -F 'dns_initial_allow=' "$pk_runtime_audit" 2>/dev/null | tail -n 1 | sed 's/.*dns_initial_allow=/dns_initial_allow=/')
    case "$pk_dns_result" in
      dns_initial_allow=called*) emit GREEN PK_DNS_HOOK "GMS-only DNS hook installed; initial OEM allow method called (netd policy readback unverified)";;
      dns_initial_allow=failed*|dns_initial_allow=error*) emit YELLOW PK_DNS_HOOK "GMS-only DNS hook initial allow reported failure: $pk_dns_result";;
      *) emit GRAY PK_DNS_HOOK "GMS-only DNS hook installed; initial allow not yet verified: ${pk_dns_result:-unknown}";;
    esac
    if grep -Fq 'first_oem_gms_dns_deny_redirected uid=' "$pk_runtime_audit" 2>/dev/null; then
      emit GREEN PK_DNS_DENY "Independent GMS-targeted OEM DNS deny request redirected successfully (once; timing in process audit)"
    else
      emit GRAY PK_DNS_DENY "No independent OEM GMS DNS deny observed yet; bootstrap allow is not evidence of one"
    fi
    if grep -Fq 'first_hit=com.miui.powerkeeper.utils.NetdExecutor#setGmsDnsBlockerState' "$pk_runtime_audit" 2>/dev/null; then
      emit GREEN PK_DNS_HIT "GMS DNS hook executed at least once (bootstrap allow counts; independent OEM deny not yet confirmed)"
    else
      emit GRAY PK_DNS_HIT "DNS method install observed; no runtime method hit yet"
    fi
  else
    emit GRAY PK_DNS_HOOK "PowerKeeper audit present; GMS DNS hook not yet confirmed installed"
  fi
else
  emit GRAY PK_DNS_HOOK "No current-boot PID-matched Hook evidence; cannot conclude a failure"
fi

idle=$(probe5 cmd deviceidle whitelist </dev/null 2>/dev/null)
if printf '%s\n' "$idle" | grep -Eq '^(system|user),com[.]google[.]android[.]gms,'; then
  emit GREEN DEVICEIDLE "native GMS exemption present"
elif printf '%s\n' "$idle" | grep -Eq '^(system|user),[A-Za-z_][A-Za-z0-9_.]*,[0-9]+$'; then
  emit YELLOW DEVICEIDLE "native GMS exemption absent from parsed readable whitelist"
else
  emit GRAY DEVICEIDLE "native GMS exemption status unavailable or malformed; no failure confirmed"
fi
backend_read_state
mounted=0 capfile=
if cache_load; then
  capfile=$CACHE_DIR/capabilities.tsv
  cache_payload_ok && cache_security_ok && cache_mounted && mounted=1
fi
backend_unverified=0
case "$phase:$mounted" in
 ACTIVE:0|MOUNTED:0) backend_unverified=1; detail='framework payload not verified in this boot; no mount failure proven';;
esac
case "$phase" in
 ACTIVE) if [ "$backend_unverified" = 1 ]; then emit GRAY BACKEND "$detail"; else emit GREEN BACKEND "$detail"; fi;;
 ERROR|QUARANTINED) emit RED BACKEND "$detail";;
 *) emit GRAY BACKEND "$detail";;
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
      emit GRAY "$feature" "generated; next normal reboot required (not a failure)"
    elif [ "$state" = ready ]; then
      emit GRAY "$feature" "cached; current-boot validation pending (not a failure)"
    else
      case "$state" in
        failed|failure|error) emit YELLOW "$feature" "confirmed feature failure: $reason";;
        *) emit GRAY "$feature" "$reason (not verified or unsupported)";;
      esac
    fi
  done < "$capfile"
  framework_label="$ready/$total"
else
  emit GRAY FEATURES "feature report unavailable; no feature failure proven"
fi
case "$level" in
 0)
    if [ "$verified_count" -gt 0 ]; then
      lamp='🟢'; label='已核验项目正常'
    else
      lamp='⚪'; label='等待有效检测'
    fi;;
 1) lamp='🟡'; label='已确认部分功能异常';;
 *) lamp='🔴'; label='检测到严重异常';;
esac
# Gray describes missing/partial evidence without elevating any warning lamp.
[ "$unknown_count" -eq 0 ] || label="$label（另${unknown_count}项待核验）"
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
