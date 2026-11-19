#!/usr/bin/env python3
"""Alpha24: run the real delayed native resolver recovery function with mocks.

No actual network, Binder, iptables mutation, phone state or GMS restart.
"""
from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
guard=(root/"module/bin/fcm_guard.sh").read_text(encoding="utf-8")
start=guard.index("dns_late_native_recovery() {")
end=guard.index("\n# Optional last resort.",start)
fragment=guard[start:end]

assert "DNSLATE_FILE=$RUNDIR/fcm_dns_late_attempt.epoch" in guard
assert 'if dns_late_native_recovery "$now" "$outage"; then' in guard
assert 'dnsresolver_binder_flush_one "$late_id"' in fragment
assert 'TransportType: CELLULAR' in fragment
assert 'Private DNS mode: OFF' in fragment
for forbidden in ("setResolverConfiguration","iptables -I","iptables -D","svc data","svc wifi","force-stop","kill -TERM","setprop"):
    assert forbidden not in fragment, forbidden

harness=r'''
set -eu
RUNDIR=$1
DOWN_FILE=$RUNDIR/down
DNSFLUSH_OUTAGE_FILE=$RUNDIR/initial
DNSFLUSH_SCOPE_FILE=$RUNDIR/scope
DNSFLUSH_FILE=$RUNDIR/flush
DNSLATE_FILE=$RUNDIR/late
DNSOK_FILE=$RUNDIR/ok
BB=mockbb
IPTABLES_WAIT_SECONDS=5
mockbb() {
  printf '%s\n' "$*" >> "$RUNDIR/probes"
  [ "$probe" = yes ] || return 1
  printf '%s\n' 'Server: 61.139.2.69' 'Address: 61.139.2.69:53' 'Name: mtalk.google.com' 'Address 1: 192.0.2.15'
}
iptables() {
  case "$box" in
    absent) return 1;;
    unknown) printf '%s\n' '-A BOX_LOCAL -p udp --dport 53 -j MARK';;
    verified) printf '%s\n' '-A BOX_LOCAL -m owner --uid-owner 0 --gid-owner 3005 -j RETURN' '-A BOX_LOCAL -p udp --dport 53 -j MARK';;
  esac
}
dns_active_default_netid() { echo "$netid"; }
run_timeout() {
  printf 'NetId: 409\n  DNS servers: # IP\n    61.139.2.69 (64, 1)\n    218.6.200.139 (7, 1)\n  Private DNS mode: %s\n  TransportType: %s\nNetId: 407\n' "$privacy" "$transport"
}
fcm_state() { echo "$state"; }
android_resolve_mtalk() {
  if [ "$already_dns" = yes ] || { [ -f "$RUNDIR/flushed" ] && [ "$recovers" = yes ]; }; then echo 192.0.2.15; fi
}
dnsresolver_binder_ready() { [ "$binder" = yes ]; }
dnsresolver_binder_flush_one() {
  printf '%s\n' "$1" >> "$RUNDIR/flushed"
}
log_msg() { printf '%s\n' "$*"; }
reset() {
  printf '1000\n' >"$DOWN_FILE"
  printf '1000\n' >"$DNSFLUSH_OUTAGE_FILE"
  printf '1000:409\n' >"$DNSFLUSH_SCOPE_FILE"
  printf '1060\n' >"$DNSFLUSH_FILE"
  rm -f "$DNSLATE_FILE" "$DNSOK_FILE" "$RUNDIR/flushed" "$RUNDIR/probes" "$RUNDIR/fcm_dns_late_probe.state" "$RUNDIR/fcm_dns_late_reproof.epoch" "$RUNDIR/fcm_dns_late_confirmed_failed.state" "$RUNDIR/unified.conf"
  netid=409; state=disconnected; transport=CELLULAR; privacy=OFF; probe=yes; recovers=yes; binder=yes; box=absent; already_dns=no
}
no_flush() {
  if dns_late_native_recovery "$@"; then echo 'Unexpected recovery'; exit 1; fi
  test ! -e "$RUNDIR/flushed"
}
'''
checks=r'''
reset; dns_late_native_recovery 1360 360
test "$(cat "$RUNDIR/flushed")" = 409
test "$(cat "$DNSOK_FILE")" = 1360
if dns_late_native_recovery 1400 400; then exit 5; fi
test "$(wc -l < "$RUNDIR/flushed")" -eq 1
test -s "$RUNDIR/dns-late-native.latest.txt"
echo PASS_recovery_and_single_shot
reset; state=connected; no_flush 1360 360; echo PASS_connected_no_flush
reset; transport=WIFI; no_flush 1360 360; echo PASS_wifi_no_flush
reset; netid=410; no_flush 1360 360; echo PASS_changed_netid_no_flush
reset; probe=no; no_flush 1360 360; echo PASS_upstream_failure_no_flush
reset; privacy=STRICT; no_flush 1360 360; echo PASS_private_dns_no_flush
reset; recovers=no
if dns_late_native_recovery 1360 360; then exit 6; fi
test "$(wc -l < "$RUNDIR/flushed")" -eq 1
test ! -e "$DNSOK_FILE"
if dns_late_native_recovery 1400 400; then exit 7; fi
test "$(wc -l < "$RUNDIR/flushed")" -eq 1
echo PASS_failed_flush_no_false_recovery
printf '%s\n' 'FCM_CELLULAR_REBIND=1' > "$RUNDIR/unified.conf"
if dns_late_native_recovery 2260 1260; then exit 9; fi
test "$(cat "$RUNDIR/fcm_dns_late_confirmed_failed.state")" = '1000 409 2260'
test "$(wc -l < "$RUNDIR/flushed")" -eq 1
if dns_late_native_recovery 2300 1300; then exit 10; fi
test "$(cat "$RUNDIR/fcm_dns_late_confirmed_failed.state")" = '1000 409 2260'
echo PASS_reproof_without_second_flush
reset; no_flush 1359 359; echo PASS_wait_after_initial_flush
reset; already_dns=yes; no_flush 1360 360; echo PASS_native_dns_already_recovered
reset; binder=no; no_flush 1360 360; echo PASS_unverified_Binder
reset; box=unknown; no_flush 1360 360; test ! -e "$RUNDIR/probes"; echo PASS_unknown_Box_route
reset; box=verified; dns_late_native_recovery 1360 360
grep -q 'su -g 3005 0 -c' "$RUNDIR/probes"
echo PASS_verified_Box_direct_query
'''
with tempfile.TemporaryDirectory(prefix="fcm-alpha24-") as t:
    directory=Path(t)
    file=directory/"harness.sh"
    file.write_text(harness+"\n"+fragment+"\n"+checks,encoding="utf-8")
    result=subprocess.run(["sh",str(file),str(directory)],check=True,capture_output=True,text=True,timeout=20)
    print(result.stdout,end="")
print("ALPHA24_BOUNDED_NATIVE_DNS_RECOVERY_CONTRACT_PASS")
