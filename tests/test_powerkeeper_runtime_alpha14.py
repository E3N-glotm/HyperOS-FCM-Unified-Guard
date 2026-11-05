#!/usr/bin/env python3
"""alpha14: test source contract for one-shot OEM UID DNS recovery and audit.
No OEM services, powerkeeper process, or real netd state are changed.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
entry = (root / "powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimeEntry.java").read_text()
policy = (root / "powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimePolicy.java").read_text()
status = (root / "module/bin/health_status.sh").read_text()

checks = {
    "audit file is app-private Device-Encrypted storage": (
        "createDeviceProtectedStorageContext()" in entry
        and 'RUNTIME_AUDIT_NAME = "fcmu_pk_runtime_alpha14.tsv"' in entry
        and "de.getFilesDir()" in entry
    ),
    "audit is one-shot and bounded, not polling": (
        "invokedOnce.compareAndSet(false, true)" in entry
        and "out.length() > 8192" in entry
        and "runtimeAudit(auditContext, \"first_hit=\"" in entry
    ),
    "only PowerKeeper can write this audit": (
        '"com.miui.powerkeeper".equals(context.getPackageName())' in entry
    ),
    "unknown OEM APK fails closed": (
        "VERIFIED_GMS_DNS_APK_SHA256" in entry
        and "MessageDigest.getInstance(\"SHA-256\")" in entry
        and "if (!verified || uid < 10000" in entry
    ),
    "GMS package UID discovered dynamically": (
        "getPackageUid(" in entry
        and "PowerKeeperRuntimePolicy.GMS" in entry
    ),
    "DNS initial rule cleared only if real hook installed": (
        '"hook_installed".equals(' in entry
        and 'report.results().get("pk.firewall.gmsDnsUidRule")' in entry
        and "restoreGmsDnsOnce(context, gmsUid, dnsVerified, report);" in entry
    ),
    "OEM allow invocation targets only actual GMS": (
        'getDeclaredMethod(' in entry
        and '"setGmsDnsBlockerState", int.class, boolean.class' in entry
        and "method.invoke(null, Integer.valueOf(uid), Boolean.FALSE);" in entry
    ),
    "ordinary non-GMS behavior unchanged": (
        "((Integer)args[0]).intValue() != verifiedGmsUid" in policy
        and "return original.call(receiver, args);" in policy
    ),
    "current-boot health status distinguishes install from hit": (
        'pk_audit_modified' in status
        and 'pk_boot_epoch' in status
        and "hook pk.firewall.gmsDnsUidRule=hook_installed" in status
        and "first_hit=com.miui.powerkeeper.utils.NetdExecutor#setGmsDnsBlockerState" in status
    ),
}
for name, passed in checks.items():
    if not passed:
        raise AssertionError(name)
    print("PASS", name)
print("PASS alpha14: one-shot scoped GMS DNS restore + auditable runtime hooks")
