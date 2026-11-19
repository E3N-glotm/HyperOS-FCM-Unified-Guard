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
settings() { case "$3" in mobile_data) if [ -f "$RUNDIR/mobile" ]; then cat "$RUNDIR/mobile"; else echo "${MOBILE:-1}"; fi;; private_dns_mode) echo "${PRIVATE:-off}";; esac; }
run_timeout() { case "$1" in svc) shift; svc "$@"; return $?;; esac; case "$2" in power) echo "mWakefulness=${WAKE:-Dozing}";; telephony.registry) echo "mCallState=${CALL:-0}";; audio) echo "- Actual mode = ${AUDIO:-MODE_NORMAL}";; tethering) echo "Upstream wanted: ${TETHER:-false}";; connectivity) echo 'Active default network: 193'; [ "${VPN:-0}" = 0 ] || echo 'NetworkAgentInfo{ Transports: VPN';; esac; }
dns_active_default_netid() { echo "${NETID:-193}"; }
fcm_state() { echo "${FCM:-disconnected}"; }
android_resolve_mtalk() { [ "${DNS:-0}" = 0 ] || echo 192.0.2.1; }
svc() {
  printf '%s\n' "$*" >> "$RUNDIR/calls"
  [ "${NO_EFFECT:-0}" = 0 ] || return 0
  [ "${BINDER_ERROR:-0}" = 0 ] || { echo 'cmd: Failed transaction'; return 0; }
  case "$2" in disable) echo 0 > "$RUNDIR/mobile";; enable) echo 1 > "$RUNDIR/mobile";; esac
}
sleep() { :; }
'''
cases = [
    ('default_off', '', '', False),
    ('eligible', 'FCM_CELLULAR_REBIND=1', '', True),
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
        subprocess.run(['sh', '-c', script, 'test', tmp.replace('\\', '/')], check=True)
        actual = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
        assert actual == (['data disable', 'data enable'] if eligible else []), (name, actual)
        print('PASS', name)
print('ALPHA26_OPT_IN_CELLULAR_REBIND_PASS')
for mode in ('NO_EFFECT=1', 'BINDER_ERROR=1'):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'unified.conf').write_text('FCM_CELLULAR_REBIND=1\n', encoding='utf-8')
        script = mock + '\n' + fn + '\n' + mode + '\n' + 'if dns_cellular_rebind_recovery "$now" 123; then exit 8; fi\n'
        subprocess.run(['sh', '-c', script, 'test', tmp.replace('\\', '/')], check=True)
        assert (root / 'calls').read_text().splitlines() == ['data disable', 'data enable'], mode
        print('PASS no false recovery:', mode)
