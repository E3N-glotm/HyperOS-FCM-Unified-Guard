#!/usr/bin/env python3
"""alpha17: source-level safety contracts for differential GMS DNS recovery.

Live Android post-boot verification is separate from these offline checks.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
guard=(root/"module/bin/fcm_guard.sh").read_text()
helper=(root/"module/bin/fcm_dns_box_repair.sh").read_text()
checks={
  "helper still supports alpha16 exact stale source evidence":
    "case \"$mode\" in probe|repair|fallback)" in helper and
    "find_unbound_failure || exit 0" in helper,
  "guard calls fallback only inside observed GMS Android DNS failure":
    guard.index('if [ -z "$android_ip" ]; then') <
    guard.index('fcm_dns_box_repair.sh" fallback "$down_since"') <
    guard.index('rate_limited_dns_log "$now" "GMS UNKNOWN_HOST'),
  "guard requires 15-minute outage before considering fallback":
    'elif [ "$outage" -ge 900 ]' in guard,
  "fallback verifies exact active FCM outage identity":
    'read -r real_down < "$RUNDIR/fcm_down_since.epoch"' in helper and
    '[ "$real_down" = "$outage_stamp" ]' in helper,
  "fallback only with 15min to 24hour actual outage":
    '[ "$outage_age" -ge 900 ] && [ "$outage_age" -le 86400 ]' in helper,
  "fallback exact GMS UID identity dynamically confirmed":
    'pm list packages -U com.google.android.gms' in helper and
    'case "$gms_uid" in' in helper,
  "fallback demands that Box DNS UDP capture is active":
    "iptables -w 5 -t mangle -S BOX_LOCAL" in helper and
    "--dport 53 .*MARK" in helper,
  "fallback demands valid IPv4 route and mature current proxy PID":
    'ip -4 route get 223.5.5.5' in helper and
    'process_age=$((up_seconds-process_ticks/hz))' in helper and
    '[ "$process_age" -ge 1200 ]' in helper,
  "fallback rechecks GMS UID libc resolver failure and filters tooling errors":
    "uid_lookup=$(busybox timeout 7 su -s /system/bin/sh" in helper and
    "unknown host|bad address|name or service not known|temporary failure in name resolution" in helper and
    "if printf '%s\\n' \"$uid_lookup\" | grep -Eq '^PING" in helper,
  "fallback requires functioning independent explicit upstream DNS":
    'su -g 3005 0 -c' in helper and
    'su -g 0 0 -c' in helper and
    '[ "$physical_dns_ok" = 1 ] || exit 0' in helper and
    '[ "$box_dns_ok" = 0 ] ||' in helper and
    '223.5.5.5 61.139.2.69' in helper,
  "fallback at most once each outage and at least 6h apart":
    'fallback_outage.epoch' in helper and
    'fallback_last.epoch' in helper and
    '[ $((now_epoch-last_fallback)) -ge 21600 ]' in helper,
  "fallback DNS differential probed once every 15 minutes max":
    'fallback_probe.epoch' in helper and
    '[ $((now_epoch-last_probe)) -ge 900 ]' in helper,
  "never restart an intentionally stopped Box or arbitrary process":
    '"$BOXDIR/manual"' in helper and
    '/data/adb/modules/box_for_root/disable' in helper and
    '"$proxy_name" = "sing-box"' in helper,
  "only Box service manager is restarted, not GMS or network stack":
    '/system/bin/sh "$SERVICE" restart' in helper and
    not any(x in helper for x in ('svc data disable','svc wifi disable','am force-stop','killall com.google.android.gms')),
  "healthy FCM path untouched":
    guard.index('case "$state" in') < guard.index('fcm_dns_box_repair.sh" fallback "$down_since"'),
}
for label,passed in checks.items():
    assert passed,label
    print("PASS",label)
print("ALPHA17_GMS_DNS_DIFFERENTIAL_GATED_RECOVERY_CONTRACT_PASS")
