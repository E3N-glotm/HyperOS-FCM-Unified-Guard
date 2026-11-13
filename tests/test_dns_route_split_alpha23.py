#!/usr/bin/env python3
"""alpha23: distinguish physical DNS from Box-marked root DNS.

Execute actual source gate from fcm_dns_box_repair.sh with fake commands. No
iptables writes, network queries, GMS/Box restarts, or phone state changes.
"""
from pathlib import Path
import os
import subprocess
import tempfile

base=Path(__file__).resolve().parents[1]
guard=(base/"module/bin/fcm_guard.sh").read_text()
helper=(base/"module/bin/fcm_dns_box_repair.sh").read_text()
diag=(base/"module/bin/fcm_dns_differential_diag.sh").read_text()

assert "DNSFLUSH_OUTAGE_FILE=$RUNDIR/fcm_dns_flush_outage.epoch" in guard
assert "dns_active_default_netid()" in guard
assert "dumpsys connectivity" in guard
assert 'dns_netids | grep -Fxq "$default_id"' in guard
assert '[ "$(cat "$DNSFLUSH_OUTAGE_FILE" 2>/dev/null)" != "$outage_stamp" ]' in guard
assert 'for netid in $live_netids' not in guard
assert "su -g 3005 0 -c" in helper
assert "su -g 0 0 -c" in helper
assert "su -g 3005 0 -c" in diag
assert "su -g 0 0 -c" in diag
assert "both_dns_paths_work_gms_native_fails_not_box_proven" in diag
assert "physical_dns_ok_box_captured_dns_failed" in diag
assert "root_gms_dns_differential_present" not in diag
assert "box_dns_ok" in helper and "physical_dns_ok" in helper
assert "fallback_outage.epoch" in helper
assert "fallback_last.epoch" in helper
assert "21600" in helper
assert '/system/bin/sh "$SERVICE" restart' in helper
for forbidden in ("svc data disable","svc wifi disable","force-stop com.google.android.gms"):
    assert forbidden not in helper
print("PASS source: active default netId, once per outage, Box-only gates")

begin=helper.index("  # alpha23: the previous 'root resolves, GMS does not' gate was wrong.")
end=helper.index("  # A single evidence-gated restart remains possible",begin)
fragment=helper[begin:end]

def put(path,data):
    path.write_text(data)
    path.chmod(0o755)

with tempfile.TemporaryDirectory(prefix="fcm-dns-split-alpha23-") as tmp:
    p=Path(tmp)
    bin=p/"bin"
    bin.mkdir()
    put(bin/"iptables", """#!/bin/sh
if [ "$MOCK_RULES" != 1 ]; then exit 1; fi
printf '%s\n' '-A BOX_LOCAL -m owner --uid-owner 0 --gid-owner 3005 -j RETURN'
""")
    put(bin/"ip", """#!/bin/sh
if [ "$MOCK_RULES" != 1 ]; then exit 1; fi
if [ "$2" = rule ]; then
  echo '100: from all fwmark 0x1000000/0x1000000 lookup 2024'
elif [ "$2" = route ]; then
  echo 'local default dev lo scope host'
fi
""")
    put(bin/"busybox", """#!/bin/sh
if [ "$1" != timeout ]; then exit 6; fi
shift 2
if [ "$1" != su ]; then exit 7; fi
shift
if [ "$1" != -g ]; then exit 8; fi
case "$2" in
  3005) test "$MOCK_PHYSICAL" = 1 || exit 9;;
  0)    test "$MOCK_BOX" = 1 || exit 9;;
  *) exit 9;;
esac
printf '%s\n' 'Server:    223.5.5.5' 'Name:      mtalk.google.com' 'Address 1: 192.179.26.188'
""")
    script=p/"harness.sh"
    script.write_text("#!/bin/sh\n"
                      'OUTLOG="$MOCK_ROOT/out.log"\noutage_age=1000\n'
                      +fragment+
                      '\nprintf "RECOVERY_ELIGIBLE\\n"\n')
    env={**os.environ,"PATH":str(bin)+os.pathsep+os.environ["PATH"],"MOCK_ROOT":str(p),"MOCK_RULES":"1"}
    cases=[
        ("both work => no restart",1,1,1,False),
        ("physical good, Box broken => eligible",1,1,0,True),
        ("physical broken, Box good => no restart",1,0,1,False),
        ("both broken => no restart",1,0,0,False),
        ("Box route not verified => fail closed",0,1,0,False),
    ]
    for title,rules,phys,box,expected in cases:
        result=subprocess.run(["sh",str(script)],env={**env,
                "MOCK_RULES":str(rules),"MOCK_PHYSICAL":str(phys),
                "MOCK_BOX":str(box)},capture_output=True,text=True,
                timeout=5,check=True)
        got="RECOVERY_ELIGIBLE" in result.stdout
        assert got == expected,(title,result.stdout,result.stderr)
        print("PASS",title)
print("ALPHA23_PHYSICAL_VS_BOX_DNS_DIFFERENTIAL_CONTRACT_PASS")
