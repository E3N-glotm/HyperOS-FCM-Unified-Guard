#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GUARD="$ROOT/module/bin/fcm_guard.sh"
FAIL() { echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'alt2-mtalk.google.com' "$GUARD" || FAIL "alternate FCM host unavailable"
grep -Fq '5228|5229|5230|443' "$GUARD" || FAIL "MCS TCP443 socket not recognized"
grep -Fq '[ "$outage" -ge 1800 ]' "$GUARD" || FAIL "no 30-minute fall-back threshold"
grep -Fq '[ "$verified_mcs" = 1 ] || [ "$attempts" -lt 2 ]' "$GUARD" ||
  FAIL "unproved restart escalation not limited"
grep -Fq 'actual_uid=$(awk' "$GUARD" || FAIL "target GMS UID not verified"
grep -Fq 'fcm_mcs_endpoint_socket_ready "$endpoint"' "$GUARD" ||
  FAIL "recovery must verify a genuine GMS socket"

functions="$(sed -n '/^fcm_mcs_endpoint_socket_ready() {/,/^}/p' "$GUARD")
$(sed -n '/^fcm_default_net_validated() {/,/^}/p' "$GUARD")"
eval "$functions"
MODDIR="$ROOT/module"
gms_uid_for_probe() { echo 10139; }
ss() { :; }
run_timeout() {
  if [ "$1" = ss ]; then printf '%s\n' "$SS_RESULT"; return 0; fi
  if [ "$1" = dumpsys ] && [ "$2" = connectivity ]; then
    printf '%s\n' "$NETWORK_RESULT"; return 0
  fi
  return 1
}
SS_RESULT='0 0 [::ffff:10.0.0.2]:44580 [::ffff:172.217.78.188]:443 users:(("gle.android.gms",pid=7891,fd=146)) uid:10139 ino:260735 sk:2384'
fcm_mcs_endpoint_socket_ready 'connected=alt2-mtalk.google.com/172.217.78.188,port=443' ||
  FAIL "valid alternate MCS connection rejected"
if fcm_mcs_endpoint_socket_ready 'connected=example.com/172.217.78.188,port=443'; then
  FAIL "arbitrary TCP443 falsely accepted"
fi
if fcm_mcs_endpoint_socket_ready 'connected=alt2-mtalk.google.com/172.217.78.187,port=443'; then
  FAIL "wrong MCS peer falsely accepted"
fi
NETWORK_RESULT='Active default network: 299
NetworkAgentInfo{network{299} Score(EVER_VALIDATED) nc{[ Transports: WIFI Capabilities: INTERNET&VALIDATED LinkUpBandwidth>=200Kbps]}'
fcm_default_net_validated || FAIL "validated network not recognized"
NETWORK_RESULT='Active default network: 299
NetworkAgentInfo{network{299} Score(EVER_VALIDATED) nc{[ Transports: WIFI Capabilities: INTERNET LinkUpBandwidth>=200Kbps]}'
if fcm_default_net_validated; then FAIL "unvalidated network accepted"; fi
echo 'Unified MCS443 bounded auto-recovery regression: PASS'
