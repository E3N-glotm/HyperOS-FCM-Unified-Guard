from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'module/bin/fcm_guard.sh').read_text(encoding='utf-8')
fn = source[source.index('dns_cellular_rebind_recovery() {'):source.index('\nrate_limited_dns_log() {')]
mock = r'''
RUNDIR=$1
DNSLATE_FAILED_FILE=$RUNDIR/failure
DOWN_FILE=$RUNDIR/down
now=30000
printf '%s\n' 123 > "$DOWN_FILE"
printf '%s\n' '123 193 30000' > "$DNSLATE_FAILED_FILE"
log_msg() { :; }
rb_wake_acquire() { [ "${WAKELOCK:-1}" = 1 ]; }
rb_wake_release() { printf 'released\n' >> "$RUNDIR/wakelock"; }
settings() {
  if [ "$1" = list ]; then
    value=$(cat "$RUNDIR/mobile" 2>/dev/null || echo "${MOBILE:-1}")
    if [ "${SLOTS:-0}" = 1 ]; then
      echo "mobile_data=${MOBILE:-0}"
      if [ -f "$RUNDIR/mobile" ]; then echo "mobile_data0=$value"; echo "mobile_data1=$value"
      else echo "mobile_data0=${SLOT0:-1}"; echo "mobile_data1=${SLOT1:-1}"; fi
    else echo "mobile_data=$value"; fi
    [ "${BAD:-0}" = 0 ] || echo 'mobile_data0=unknown'
    return 0
  fi
  case "$3" in private_dns_mode) echo "${PRIVATE:-off}";; esac
}
run_timeout() {
  case "$1" in
    svc|settings) call=$1; shift; "$call" "$@"; return $?;;
    cmd) if [ "$4" = help ]; then
        [ "${PHONE:-0}" = 1 ] && printf '%s\n' 'data enable: enable' 'data disable: disable'
      else svc data "$4"; fi; return $?;;
  esac
  case "$2" in
    power) echo "mWakefulness=${WAKE:-Dozing}";;
    telephony.registry) echo "mCallState=${CALL:-0}";;
    isub) printf '%s\n' "defaultDataSubId=${DEFAULT_SUB:-2}" "activeDataSubId=${ACTIVE_SUB:-2}";;
    audio) echo "- Actual mode = ${AUDIO:-MODE_NORMAL}";;
    tethering) echo "Upstream wanted: ${TETHER:-false}";;
    connectivity)
      echo 'Active default network: 193'
      if [ "$(cat "$RUNDIR/mobile" 2>/dev/null || echo 1)" != 0 ] || [ "${TEARDOWN_STUCK:-0}" = 1 ]; then
        echo "NetworkAgentInfo{network{193} Transports: ${TRANSPORT:-CELLULAR} Capabilities: INTERNET SubscriptionIds: {${NET_SUB:-2}}"
      fi
      [ "${VPN:-0}" = 0 ] || echo 'NetworkAgentInfo{ Transports: VPN'
      return 0;;
  esac
}
dns_active_default_netid() { echo "${NETID:-193}"; }
fcm_state() { echo "${FCM:-disconnected}"; }
android_resolve_mtalk() { [ "${DNS:-0}" = 0 ] || echo 192.0.2.1; }
svc() {
  printf '%s\n' "$*" >> "$RUNDIR/calls"
  [ "${NO_EFFECT:-0}" = 0 ] || return 0
  [ "${BINDER_ERROR:-0}" = 0 ] || { echo 'cmd: Failed transaction'; return 0; }
  if [ "${ENABLE_FAIL_ONCE:-0}" = 1 ] && [ "$2" = enable ] && [ ! -f "$RUNDIR/enable_failed" ]; then
    : > "$RUNDIR/enable_failed"
    echo 'cmd: Failed transaction'
    return 0
  fi
  case "$2" in disable) echo 0 > "$RUNDIR/mobile";; enable) echo 1 > "$RUNDIR/mobile";; esac
}
sleep() { :; }
'''
cases = [
    ('default_off', '', '', False),
    ('eligible', 'FCM_CELLULAR_REBIND=1', '', True),
    ('dual_sim_stale_global', 'FCM_CELLULAR_REBIND=1', 'SLOTS=1; MOBILE=0; PHONE=1', True),
    ('dual_sim_asymmetric', 'FCM_CELLULAR_REBIND=1', 'SLOTS=1; MOBILE=0; SLOT1=0', False),
    ('dual_sim_both_off', 'FCM_CELLULAR_REBIND=1', 'SLOTS=1; SLOT0=0; SLOT1=0', False),
    ('malformed_slot_data', 'FCM_CELLULAR_REBIND=1', 'SLOTS=1; BAD=1', False),
    ('wifi_not_cellular', 'FCM_CELLULAR_REBIND=1', 'TRANSPORT=WIFI', False),
    ('wrong_subscription', 'FCM_CELLULAR_REBIND=1', 'NET_SUB=1', False),
    ('wrong_active_subscription', 'FCM_CELLULAR_REBIND=1', 'ACTIVE_SUB=1', False),
    ('subscription_unknown', 'FCM_CELLULAR_REBIND=1', 'DEFAULT_SUB=-1', False),
    ('no_wakelock', 'FCM_CELLULAR_REBIND=1', 'WAKELOCK=0', False),
    ('screen_on', 'FCM_CELLULAR_REBIND=1', 'WAKE=Awake', False),
    ('active_call', 'FCM_CELLULAR_REBIND=1', 'CALL=2', False),
    ('netid_changed', 'FCM_CELLULAR_REBIND=1', 'NETID=194', False),
    ('fcm_online', 'FCM_CELLULAR_REBIND=1', 'FCM=connected', False),
    ('dns_already_recovered', 'FCM_CELLULAR_REBIND=1', 'DNS=1', False),
    ('stale_evidence', 'FCM_CELLULAR_REBIND=1', 'now=30200', False),
    ('mobile_data_disabled', 'FCM_CELLULAR_REBIND=1', 'MOBILE=0', False),
    ('private_dns_enabled', 'FCM_CELLULAR_REBIND=1', 'PRIVATE=hostname', False),
    ('active_audio_call', 'FCM_CELLULAR_REBIND=1', 'AUDIO=MODE_IN_COMMUNICATION', False),
    ('tethering_active', 'FCM_CELLULAR_REBIND=1', 'TETHER=true', False),
    ('vpn_active', 'FCM_CELLULAR_REBIND=1', 'VPN=1', False),
    ('cooldown', 'FCM_CELLULAR_REBIND=1', 'printf "%s\\n" "122 29900" > "$RUNDIR/fcm_dns_cellular_rebind.state"', False),
]
for name, cfg, variation, eligible in cases:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'unified.conf').write_text(cfg + '\n', encoding='utf-8')
        script = mock + '\n' + fn + '\n' + variation + '\n' + 'dns_cellular_rebind_recovery "$now" 123 || true\ndns_cellular_rebind_recovery "$now" 123 || true\n'
        (root / 'case.sh').write_text(script, encoding='utf-8', newline='\n')
        subprocess.run(['sh', (root / 'case.sh').as_posix(), tmp.replace('\\', '/')], check=True)
        actual = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
        assert actual == (['data disable', 'data enable'] if eligible else []), (name, actual)
        assert (root / 'wakelock').exists() == eligible, name
        print('PASS', name)
print('ALPHA26_OPT_IN_CELLULAR_REBIND_PASS')
for mode in ('NO_EFFECT=1', 'BINDER_ERROR=1', 'TEARDOWN_STUCK=1', 'ENABLE_FAIL_ONCE=1'):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'unified.conf').write_text('FCM_CELLULAR_REBIND=1\n', encoding='utf-8')
        script = mock + '\n' + fn + '\n' + mode + '\n' + 'if dns_cellular_rebind_recovery "$now" 123; then exit 8; fi\n'
        (root / 'case.sh').write_text(script, encoding='utf-8', newline='\n')
        subprocess.run(['sh', (root / 'case.sh').as_posix(), tmp.replace('\\', '/')], check=True)
        expected = ['data disable', 'data enable', 'data enable'] if mode == 'ENABLE_FAIL_ONCE=1' else ['data disable', 'data enable']
        assert (root / 'calls').read_text().splitlines() == expected, mode
        assert (root / 'wakelock').read_text().strip() == 'released', mode
        if mode in ('TEARDOWN_STUCK=1', 'ENABLE_FAIL_ONCE=1'):
            assert (root / 'mobile').read_text().strip() == '1', mode
        print('PASS no false recovery:', mode)
