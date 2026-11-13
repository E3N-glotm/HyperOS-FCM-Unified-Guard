#!/usr/bin/env python3
"""Safety and diagnostics regression for alpha18.

No network or Android process changes are performed by this host-side test;
separate isolated Android tests check runtime behavior.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
guard = (root / "module/bin/fcm_guard.sh").read_text(encoding="utf-8")
diag = (root / "module/bin/fcm_dns_differential_diag.sh").read_text(encoding="utf-8")
helper = (root / "module/bin/fcm_dns_box_repair.sh").read_text(encoding="utf-8")

checks = {
    "flight recorder only runs within ongoing GMS DNS failure, not healthy FCM":
        guard.index('if [ -z "$android_ip" ]; then') <
        guard.index('fcm_dns_differential_diag.sh') <
        guard.index('rate_limited_dns_log "$now" "GMS UNKNOWN_HOST'),
    "diagnostic invocation requires at least fifteen minutes outage":
        'elif [ "$outage" -ge 900 ]' in guard and
        'fcm_dns_differential_diag.sh" \\' in guard,
    "diagnostic validates exact persisted current outage identity":
        'REAL_OUTAGE < "$RUNDIR/fcm_down_since.epoch"' in diag and
        '[ "$OUTAGE" = "$REAL_OUTAGE" ]' in diag,
    "diagnostic rate limited to one read per 15min and only when disconnected":
        '[ $((NOW-OLD)) -ge 900 ]' in diag and
        '[ "$AGE" -ge 900 ] && [ "$AGE" -le 86400 ]' in diag,
    "history bounded and fixed schema":
        'busybox tail -n 96 "$HISTORY"' in diag and
        'outage_sec=%s' in diag and
        'gate=%s' in diag,
    "all major fail closed gates provide a reason":
        all(gate in diag for gate in (
            'user_disabled_box','box_pid_missing','box_not_running',
            'box_dns_capture_missing','no_ipv4_route','gms_uid_mismatch',
            'box_recently_started','gms_dns_already_restored',
            'gms_query_not_conclusive','physical_upstream_or_transport_unavailable',
            'physical_upstream_bypass_unverified','box_egress_not_proven',
            'box_path_fault_but_recovery_rate_limited',
            'both_dns_paths_work_gms_native_fails_not_box_proven',
            'physical_dns_ok_box_captured_dns_failed')),
    "GMS-UID and explicit upstream paths distinguished":
        '/system/bin/ping -c 1 -W 1 mtalk.google.com' in diag and
        'su -g 3005 0 -c' in diag and
        'su -g 0 0 -c' in diag and
        'busybox nslookup mtalk.google.com $SERVER' in diag,
    "diagnostic does not mutate network/Box/GMS state":
        not re.search(
            r"(?m)^\\s*(?:iptables|ip6tables)\\b[^\\n]*\\s-(?:A|I|D|F|R|P|N|X|Z)\\b"
            r"|^\\s*ip\\s+(?:rule|route)\\s+(?:add|del|replace)\\b"
            r"|^\\s*(?:svc|settings\\s+put|am\\s+broadcast|killall|pkill)\\b", diag
        ) and ' "$SERVICE" restart' not in diag,
    "original alpha17 selective Box recovery unchanged":
        'fallback "$down_since"' in guard and
        'fallback_outage.epoch' in helper and
        'MIN_RESTART_GAP=1800' in helper,
    "soft reconnect initial cadence preserved":
        'soft_gap=180' in guard and 'soft_gap=300' in guard,
    "only confirmed ongoing DNS failure slows futile broadcasts":
        'if [ "${3:-}" = dns-failed ] && [ "$soft_outage" -ge 900 ]' in guard
        and 'soft_gap=1800' in guard
        and 'soft_reconnect_if_stalled "$now" "$outage" dns-failed' in guard,
    "GMS soft reconnect remains native and never forces GMS restart inside the branch":
        'com.google.android.intent.action.GCM_RECONNECT' in guard and
        'restarting GMS-host' in guard,
}
for name, ok in checks.items():
    if not ok:
        raise AssertionError(name)
    print("PASS", name)
print("ALPHA18_FCM_DNS_FLIGHT_RECORDER_AND_POWER_POLICY_PASS")
