#!/usr/bin/env python3
"""Socket selection and fail-closed/replacement/rate-limit regression."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "module/bin/fcm_socket_keepalive.sh"
line = '0 0 [::ffff:10.0.0.1]:1234 [::ffff:108.177.98.188]:5228 users:(("gle.android.gms",pid=8050,fd=145)) uid:10139 ino:26606154 sk:8dc66'
def select(data, ip="108.177.98.188", port="5228", uid="10139"):
    result = subprocess.run(["sh", "-c", '. "$1"; fcm_mcs_socket_tuple "$2" "$3" "$4"', "test", str(source), ip, port, uid],
                            input=data+"\n", text=True, capture_output=True, check=True)
    return result.stdout.strip()
assert select(line) == "8050 145 10139 26606154"
assert select(line.replace("uid:10139", "uid:9999")) == ""
assert select(line.replace("5228", "443")) == ""
assert select(line.replace("108.177.98.188", "108.177.98.189")) == ""
assert select(line.replace("ino:26606154", "")) == ""
assert select(line.replace("pid=8050,fd=145", "")) == ""
assert select(line+"\n"+line.replace("ino:26606154", "ino:26606155")) == ""
ipv6 = line.replace("[::ffff:108.177.98.188]", "[2001:db8::1]")
assert select(ipv6, ip="2001:db8::1") == "8050 145 10139 26606154"
with tempfile.TemporaryDirectory() as tmp:
    d = pathlib.Path(tmp)
    (d/"fcm-observed.endpoint").write_text("connected=mtalk.google.com/108.177.98.188,port=5228\n")
    result = subprocess.run(["sh", "-eu", "-c", '''
    . "$1"
    RUNDIR=$2 MODDIR=$2 gms_uid=10139
    ss() { :; }
    run_timeout() {
      case "$1" in
        ss) printf '%s\n' "$ROW";;
        */fcmu_socket_keepalive) printf '%s\n' "$*" >> "$RUNDIR/calls"; [ "${FAIL:-0}" = 0 ];;
        *) return 1;;
      esac
    }
    log_msg() { printf '%s\n' "$*" >> "$RUNDIR/log"; }
    ROW=$3
    fcm_socket_keepalive 1000
    fcm_socket_keepalive 1120
    [ "$(wc -l < "$RUNDIR/calls")" -eq 1 ]
    ROW=$(printf '%s\n' "$ROW" | sed 's/ino:26606154/ino:26606155/')
    fcm_socket_keepalive 1240
    [ "$(wc -l < "$RUNDIR/calls")" -eq 2 ]
    FAIL=1
    fcm_socket_keepalive 1840
    fcm_socket_keepalive 1960
    [ "$(wc -l < "$RUNDIR/calls")" -eq 3 ]
    grep -q unsupported "$RUNDIR/fcm_socket_keepalive.state"
    printf '%s\n' 'connected=unrelated.example/108.177.98.188,port=5228' > "$RUNDIR/fcm-observed.endpoint"
    fcm_socket_keepalive 2560
    [ "$(wc -l < "$RUNDIR/calls")" -eq 3 ]
    ''', "test", str(source), str(d), line], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr + result.stdout
print("PASS alpha30: exact socket selection, ambiguity/UID rejection, replacement, rate limit and unsupported fallback")
