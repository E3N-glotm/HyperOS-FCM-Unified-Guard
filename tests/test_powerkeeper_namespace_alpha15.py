#!/usr/bin/env python3
"""alpha15: guard regression for isolated OEM app storage and DNS evidence.
These checks are read-only and cannot change Android DNS policy.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
health=(root/"module/bin/health_status.sh").read_text(encoding="utf-8")
entry=(root/"powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimeEntry.java").read_text(encoding="utf-8")
policy=(root/"powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimePolicy.java").read_text(encoding="utf-8")
checks={
    "Uses PowerKeeper mount namespace, not Magisk shell root namespace":
        'pk_runtime_audit="/proc/$pk_pid/root/data/user_de/0/$pk_name/files/fcmu_pk_runtime_alpha14.tsv"' in health,
    "Requires mapped Zygisk and valid PowerKeeper PID":
        '[ "${pk_mapped:-0}" = 1 ]' in health and 'case "$pk_pid:$pk_name" in' in health,
    "Rejects historical process audit with matching boot but different PID":
        'grep -Fq "alpha14 attach_backup_completed pid=$pk_pid"' in health,
    "Maintains timestamp freshness on the same boot":
        "pk_audit_modified" in health and "pk_boot_epoch" in health,
    "Separately reports real GMS Observer and Doze installs":
        'emit GREEN PK_METHODS' in health and "hook pk.gms.updateFrameworkGmsNetStatus=hook_installed" in health,
    "Does not mistake bootstrap allow for OEM deny":
        'emit GRAY PK_DNS_DENY' in health and "bootstrap allow" in health,
    "Captures independently redirected OEM deny once":
        'private final AtomicBoolean independentDnsDenyOnce = new AtomicBoolean();' in entry
        and 'first_oem_gms_dns_deny_redirected uid=' in entry
        and "oemDnsDenyRequest && independentDnsDenyOnce.compareAndSet(false, true)" in entry,
    "Requires actual GMS UID, boolean true and specific method":
        'activeGmsDnsHookUid >= 10000 && params.length == 2' in entry
        and 'Boolean.TRUE.equals(params[1])' in entry
        and 'methodName.endsWith(".NetdExecutor#setGmsDnsBlockerState")' in entry,
    "Only activates evidence identity after successful native hook install":
        '"hook_installed".equals(report.results().get("pk.firewall.gmsDnsUidRule"))' in entry,
    "Other UIDs, non-deny actions keep original method invocation":
        "((Integer)args[0]).intValue() != verifiedGmsUid" in policy
        and "return original.call(receiver, args);" in policy,
    "No global network configuration changes or periodic monitor":
        "iptables" not in entry and "setprop" not in entry and "Thread.sleep" not in entry,
}
for name, passed in checks.items():
    if not passed:
        raise AssertionError(name)
    print("PASS",name)
print("ALPHA15_NAMESPACE_AND_INDEPENDENT_DENY_EVIDENCE_PASS")
