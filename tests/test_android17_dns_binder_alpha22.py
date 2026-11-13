#!/usr/bin/env python3
"""alpha22: execute the actual DNS-flush Shell functions with mocked services."""
from pathlib import Path
import os
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
guard=(root/"module/bin/fcm_guard.sh").read_text(encoding="utf-8")
start=guard.index("dns_netids() {")
end=guard.index("\nrate_limited_dns_log() {",start)
fragment=guard[start:end]

assert "DNSFLUSH_SCOPE_FILE=$RUNDIR/fcm_dns_flush_scope.signature" in guard
assert "service call dnsresolver 11 i32" in fragment
assert "service call dnsresolver 1" in fragment
assert '[ "$(getprop ro.build.version.sdk)" = 37 ]' in fragment
assert "underlying DNS transport remains unproven" in fragment
for forbidden in ("sh $SERVICE restart","am force-stop","iptables -I","setResolverConfiguration"):
    assert forbidden not in fragment, forbidden

def write(path, content):
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)

with tempfile.TemporaryDirectory(prefix="fcm-alpha22-") as directory:
    t=Path(directory)
    b=t/"bin"
    b.mkdir()
    write(b/"fake-bb", """#!/bin/sh
if [ "$1" = timeout ]; then shift 2; fi
exec "$@"
""")
    write(b/"getprop", '#!/bin/sh\nprintf "%s\\n" "$MOCK_SDK"\n')
    write(b/"service", """#!/bin/sh
if [ "$1" = list ]; then
  echo '177 dnsresolver: [android.net.IDnsResolver]'
elif [ "$1" = call ] && [ "$2" = dnsresolver ]; then
  if [ "$3" = 1 ]; then
    echo "Result: Parcel( 00000000 00000001 '........')"
  elif [ "$3" = 11 ]; then
    printf '%s\n' "$5" >> "$CALLS"
    if [ "$MOCK_BINDER_FAIL" = 1 ]; then
      echo "Result: Parcel( ffffffff '....')"
    else
      echo "Result: Parcel( 00000000 '....')"
    fi
  fi
fi
""")
    write(b/"dumpsys", """#!/bin/sh
if [ "$1" = dnsresolver ]; then
  printf '%s\n' 'NetId: 594' '  DNS servers: 61.139.2.69' 'NetId: 598'
elif [ "$1" = connectivity ]; then
  printf 'Active default network: %s\n' "$MOCK_DEFAULT"
fi
""")
    write(b/"ndc", "#!/bin/sh\necho '500 0 Command not recognized'\nexit 1\n")
    write(b/"cmd", "#!/bin/sh\necho 'cmd: Failure calling service netd: Failed transaction'\nexit 1\n")
    harness=t/"harness.sh"
    harness.write_text(
        'BB="$MOCK_ROOT/bin/fake-bb"\n'
        'RUNDIR="$MOCK_ROOT"\n'
        'DNSFLUSH_FILE="$MOCK_ROOT/flush.epoch"\n'
        'DNSFLUSH_SCOPE_FILE="$MOCK_ROOT/flush.scope"\n'
        'DNSFLUSH_OUTAGE_FILE="$MOCK_ROOT/flush.outage"\n'
        'DOWN_FILE="$MOCK_ROOT/outage.epoch"\n'
        'run_timeout() { "$@"; }\n'
        'log_msg() { printf "%s\\n" "$*" >> "$MOCK_ROOT/events.log"; }\n'
        +fragment+'\n'
        'flush_android_dns "$MOCK_NOW"\n',
        encoding="utf-8")
    (t/"outage.epoch").write_text("1794432797\n")
    env={**os.environ,"MOCK_ROOT":str(t),"PATH":str(b)+os.pathsep+os.environ["PATH"],
         "CALLS":str(t/"calls.log"),"MOCK_SDK":"37","MOCK_BINDER_FAIL":"0",
         "MOCK_NOW":"1794440000","MOCK_DEFAULT":"594"}
    def run(**changes):
        e={**env,**{k:str(v) for k,v in changes.items()}}
        return subprocess.run(["sh",str(harness)],env=e,capture_output=True,
                              text=True,check=True,timeout=10)
    run()
    assert (t/"calls.log").read_text().splitlines()==["594"]
    assert "binder=1" in (t/"events.log").read_text()
    assert (t/"flush.scope").read_text().startswith("1794432797:594")
    print("PASS only verified current default NetId: Android17 Binder flushNetworkCache(11)")
    run(MOCK_NOW=1794440800,MOCK_DEFAULT=598)
    assert len((t/"calls.log").read_text().splitlines())==1
    print("PASS same outage never repeats even when cellular default NetId changes")
    (t/"outage.epoch").write_text("1794440801\n")
    run(MOCK_NOW=1794440805,MOCK_DEFAULT=598)
    assert len((t/"calls.log").read_text().splitlines())==2
    print("PASS new outage can refresh caches")
    for name in ("flush.scope","flush.outage","flush.epoch","calls.log","events.log"):
        (t/name).unlink()
    run(MOCK_SDK=36)
    assert not (t/"calls.log").exists()
    assert "active default DNS cache flush unsupported/failed" in (t/"events.log").read_text()
    print("PASS unverified SDK skips transaction, old unsupported path fails closed")
    (t/"flush.epoch").unlink()
    (t/"events.log").unlink()
    run(MOCK_BINDER_FAIL=1)
    assert "active default DNS cache flush unsupported/failed" in (t/"events.log").read_text()
    assert not (t/"flush.scope").exists()
    print("PASS Binder exception is never reported as a successful flush")
print("ALPHA22_ANDROID17_RESOLVER_BINDER_RECOVERY_CONTRACT_PASS")
