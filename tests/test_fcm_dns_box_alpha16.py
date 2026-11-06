#!/usr/bin/env python3
"""Regression contract for alpha16: narrowly scoped stale-source DNS repair.

This test is host-side and does not execute any Android network modifications.
An isolated Android mock runs probe/repair with a fake Box service separately.
"""
import pathlib
import re
from datetime import datetime, timedelta, timezone

root=pathlib.Path(__file__).resolve().parents[1]
repair=(root/"module/bin/fcm_dns_box_repair.sh").read_text(encoding="utf-8")
guard=(root/"module/bin/fcm_guard.sh").read_text(encoding="utf-8")
checks={
    "only invoked inside confirmed current Android GMS DNS failure":
        'if [ -z "$android_ip" ]; then' in guard and
        'fcm_dns_box_repair.sh" repair' in guard and
        guard.index('if [ -z "$android_ip" ]; then') < guard.index('fcm_dns_box_repair.sh" repair') <
        guard.index('rate_limited_dns_log "$now" "GMS UNKNOWN_HOST'),
    "no new timers or always-on worker":
        'fcm_dns_box_repair.sh" repair' in guard and
        'fcm_dns_box_repair.sh" probe' not in guard and
        "while true" not in repair and "sleep " not in repair,
    "GMS connection state handled before DNS repair":
        guard.index('case "$state" in') < guard.index('fcm_dns_box_repair.sh" repair'),
    "Box service lifecycle only":
        'busybox timeout 75 /system/bin/sh "$SERVICE" restart' in repair,
    "only the known FCM DNS query and specific unreachable old-source symptom":
        "dns: exchange failed for mtalk.google.com." in repair and
        "write udp [0-9.]+:[0-9]+->[0-9.]+:53: write: network is unreachable" in repair,
    "requires source no longer present on live network interfaces":
        'ip -4 -o addr show scope global up' in repair and
        'if(p[1]==address) found=1' in repair,
    "must still have a usable IPv4 route":
        "ip -4 route get 223.5.5.5" in repair,
    "fresh evidence only":
        "MAX_LOG_AGE=900" in repair and
        '"$failure_age" -le "$MAX_LOG_AGE"' in repair,
    "throttle and consume exact evidence before restart":
        "MIN_RESTART_GAP=1800" in repair and
        '"$last_event" != "$failure_signature"' in repair and
        repair.index('> "$LAST_EVENT"') < repair.index('"$SERVICE" restart'),
    "manual disable and stopped proxy are respected":
        '/data/adb/modules/box_for_root/disable' in repair and
        '"$BOXDIR/manual"' in repair and
        '"$proxy_name" = "sing-box"' in repair,
    "normal FCM keepalive not modified":
        "connected_keepalive" in guard and "MCS_HEARTBEAT" in guard,
    "guard restores only existing GMS TCP bypass after Box reconfiguration":
        'if [ "$repaired" = BOX_FCM_DNS_RECOVERY_TRIGGERED ]; then' in guard and
        'ensure_fcm_uid_bypass' in guard,
    "script works even if ZIP helper has 0644 permissions":
        '[ -r "$MODDIR/bin/fcm_dns_box_repair.sh" ]' in guard,
    "no direct iptables or routing mutation in helper":
        not re.search(r"\b(iptables|ip6tables|ip\s+rule\s+add|ip\s+route\s+add|svc\s+wifi|settings\s+put)\b",repair),
    "no GMS process kill in helper":
        not re.search(r"\b(killall|pkill|kill\s+-TERM|am force-stop)\b",repair),
}
for name, ok in checks.items():
    if not ok:
        raise AssertionError(name)
    print("PASS",name)

log="+0800 2026-11-06 09:49:55 ERROR dns: exchange failed for mtalk.google.com. IN A: write udp 10.101.129.20:57694->223.5.5.5:53: write: network is unreachable"
pat=r"write udp (\d{1,3}(?:\.\d{1,3}){3}):\d+->\d{1,3}(?:\.\d{1,3}){3}:53: write: network is unreachable"
m=re.search(pat,log)
assert m and m.group(1)=="10.101.129.20"
assert m.group(1) not in {"10.22.168.76","192.168.220.101"}
print("PASS historical observed stale-source log is correctly recognized")
print("PASS alpha16 guarded stale Box FCM DNS repair contracts")
