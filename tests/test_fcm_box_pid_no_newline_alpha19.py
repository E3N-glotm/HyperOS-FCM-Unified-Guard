#!/usr/bin/env python3
"""Regression for Box4Magisk's box.pid file with no trailing newline.

The original helper erroneously treated POSIX read's EOF exit status as a
failure, even when a complete decimal PID had been read. No real processes,
network, Box services, or Android state are touched by this host-side test.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
helper = (root / "module/bin/fcm_dns_box_repair.sh").read_text()
guard = (root / "module/bin/fcm_guard.sh").read_text()
diag = (root / "module/bin/fcm_dns_differential_diag.sh").read_text()

assert 'proxy_pid=$(cat "$BOXPID" 2>/dev/null) || exit 0' in helper
assert 'read -r proxy_pid < "$BOXPID" 2>/dev/null || exit 0' not in helper
assert 'case "$proxy_pid" in \'\'|*[!0-9]*) exit 0;; esac' in helper
assert '[ "$proxy_name" = "sing-box" ] && kill -0 "$proxy_pid"' in helper
assert 'if [ "$mode" = fallback ]; then' in helper
assert '[ "$outage_age" -ge 900 ] && [ "$outage_age" -le 86400 ]' in helper
assert '[ "$real_down" = "$outage_stamp" ]' in helper
assert '[ $((now_epoch-last_fallback)) -ge 21600 ]' in helper
assert '"$STATE_DIR/fallback_outage.epoch"' in helper
assert 'busybox timeout 75 /system/bin/sh "$SERVICE" restart' in helper
assert 'fcm_dns_box_repair.sh" fallback "$down_since"' in guard
assert "root_gms_dns_differential_present" in diag

legacy = ('read -r proxy_pid < "$1" || exit 9; '
          'printf "PID:%s" "$proxy_pid"')
fixed = ('proxy_pid=$(cat "$1" 2>/dev/null) || exit 9; '
         'case "$proxy_pid" in \'\'|*[!0-9]*) exit 10;; esac; '
         'printf "PID:%s" "$proxy_pid"')


def run_script(script, path):
    return subprocess.run(
        ["sh", "-c", script, "fcm-box-pid-test", str(path)],
        capture_output=True, text=True, check=False, timeout=5
    )

with tempfile.TemporaryDirectory(prefix="fcm-alpha19-pid-") as directory:
    path = Path(directory) / "box.pid"

    # The real Box4Magisk file contains only digits, WITHOUT a final LF.
    path.write_bytes(b"13508")
    old = run_script(legacy, path)
    assert old.returncode == 9, (old.returncode, old.stdout)
    new = run_script(fixed, path)
    assert new.returncode == 0 and new.stdout == "PID:13508", new
    print("PASS: real Box PID no-newline format; old exit reproduced, fixed works")

    path.write_bytes(b"13508\n")
    check = run_script(fixed, path)
    assert check.returncode == 0 and check.stdout == "PID:13508", check
    print("PASS: traditional LF-terminated decimal PID")

    for malformed in (b"", b"13508x", b"-1", b"13508\n9999",
                      b"13508;rm -rf /", b" 13508", b"13508 123"):
        path.write_bytes(malformed)
        check = run_script(fixed, path)
        assert check.returncode == 10, (malformed, check)
    print("PASS: empty/malformed/injected/multi-line PIDs rejected")

    path.unlink()
    check = run_script(fixed, path)
    assert check.returncode == 9, check
    print("PASS: missing Box PID fails closed")

print("ALPHA19_BOX_PID_EOF_AND_FCM_DNS_RECOVERY_CONTRACT_PASS")
