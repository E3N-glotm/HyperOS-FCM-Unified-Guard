"""Regression for bounded native DNS recovery."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "module/bin/fcm_dns_hosts_fallback.sh"

def run(fn, data="", *args):
    return subprocess.run(["sh", "-c", '. "$1"; shift; "$@"', "test", str(source), fn, *args],
                          input=data, text=True, capture_output=True)

dns = """Server: 61.139.2.69
Address: 61.139.2.69
Name: mtalk.google.com
Address 1: 192.179.26.188
Address 2: 192.179.26.188
Address 3: 127.0.0.1
Address 4: 10.2.3.4
Address 5: 192.179.26.018
Address 6: 999.1.2.3
Name: unrelated.invalid
Address 1: 1.1.1.1
"""
assert run("fcm_hosts_dns_answers", dns).stdout.strip() == "192.179.26.188"
assert run("fcm_hosts_dns_answers", dns.replace("Name: mtalk.google.com", "Name: other.invalid")).stdout == ""
conn = """Active default network: 279
  NetworkAgentInfo{network{279} ni{MOBILE CONNECTED} nc{[ Transports: CELLULAR Capabilities: INTERNET&NOT_VPN ]}}
  callbackRequest: NetworkRequest [ LISTEN [ Transports: VPN Capabilities: INTERNET ] ]
"""
assert run("fcm_hosts_network_safe", conn, "279").returncode == 0
assert run("fcm_hosts_network_safe", conn, "280").returncode != 0
assert run("fcm_hosts_network_safe", conn + "  NetworkAgentInfo{network{280} ni{VPN CONNECTED} nc{[ Transports: VPN Capabilities: INTERNET ]}}\n", "279").returncode != 0
diag = """NetId: 279
  DNS servers: # IP
    240e::1 (14, 0, 0, 0, 14)
    61.139.2.69 (64, 64, 0, 0, 0)
    218.6.200.139 (1, 1, 0, 0, 0)
  Private DNS mode: OFF
  TransportType: CELLULAR
NetId: 280
  DNS servers:
    1.1.1.1 (1, 1, 0, 0, 0)
  Private DNS mode: OFF
  TransportType: WIFI
"""
assert run("fcm_hosts_dns_servers", diag, "279").stdout.split() == ["61.139.2.69", "218.6.200.139"]
assert run("fcm_hosts_dns_servers", diag, "280").stdout == ""
assert run("fcm_hosts_dns_servers", diag.replace("mode: OFF", "mode: STRICT"), "279").stdout == ""
with tempfile.TemporaryDirectory() as tmp:
    d = pathlib.Path(tmp)
    (d / "unified.conf").write_text("FCM_DNS_HOSTS_FALLBACK=0\n")
    result = subprocess.run(["sh", "-c", '''
      . "$1"
      RUNDIR=$2
      dns_active_default_netid() { echo UNEXPECTED; exit 88; }
      fcm_hosts_fallback 10000 9000 1000 9001 && exit 2
      fcm_hosts_fallback 10000 9900 100 9901 && exit 3
      test ! -e "$RUNDIR/fcm_dns_hosts_fallback.state"
    ''', "test", str(source), str(d)], capture_output=True, text=True)
    assert result.returncode == 0 and "UNEXPECTED" not in result.stdout
assert run("fcm_hosts_ipv4", "0.1.2.3\n224.0.0.1\n192.168.0.1\n100.64.0.1\n").stdout == ""
print("PASS alpha31 DNS answer, transport/VPN/private DNS and disabled/short outage gates")
