#!/usr/bin/env python3
"""alpha13 source-level policy gate regression; does not load Zygisk or mutate OEM."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
entry = (root / "powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimeEntry.java").read_text()
policy = (root / "powerkeeper-runtime/src/io/github/e3n/fcmu/pk/PowerKeeperRuntimePolicy.java").read_text()
assert "164f2b6271eef11afaf5c97984011f01329173099accf69bada3b815a26cbd44" in entry
assert 'MessageDigest.getInstance("SHA-256")' in entry
assert 'context.getApplicationInfo().sourceDir' in entry
assert 'context.getPackageManager().getPackageUid(' in entry
assert 'dnsVerified && gmsUid >= 10000' in entry
assert 'context.getClassLoader(), names, new NativeInstaller(),' in entry
assert 'pk.firewall.gmsDnsUidRule' in policy
assert 'candidate_unverified' in policy
assert '!verifiedGmsDnsSemantics || verifiedGmsUid < 10000' in policy
assert '((Integer)args[0]).intValue() != verifiedGmsUid' in policy
assert 'narrowed[1] = Boolean.FALSE' in policy
assert 'return original.call(receiver, narrowed)' in policy
assert 'setGmsDnsBlockerState' in policy
print("PASS alpha13: APK SHA fingerprint + runtime GMS UID required; other UIDs and unknown ROM fail closed")
