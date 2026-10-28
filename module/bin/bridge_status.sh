#!/system/bin/sh
# Read-only: installed != enabled != currently hooked.
PKG=io.github.e3n.hyperos.fcmlive
EXPECTED=7ef95f78db07fa41d723fca0792b92eb5b1efa1add91f3858bf52e6ce26cb0ae
apk=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
if [ ! -r "$apk" ]; then
  echo 'BRIDGE_MISSING: install bundled E3N FCM Live bridge; enable system and com.miui.powerkeeper scopes'
  exit 1
fi
actual=$(sha256sum "$apk" 2>/dev/null | cut -d' ' -f1)
if [ "$actual" = "$EXPECTED" ]; then
  echo 'BRIDGE_BINARY: verified baseline v1.4.1-e3n-os4 (SHA-256 match)'
else
  echo 'BRIDGE_BINARY: different build; parity with tested baseline is unverified'
fi
for process in system_server com.miui.powerkeeper; do
  pid=$(pidof "$process" 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] || { echo "BRIDGE_HOOKS $process: process absent"; continue; }
  # Match current PID, not a previous boot or crashed process.
  lines=$(grep -h -F '[io.github.e3n.hyperos.fcmlive,' /data/adb/lspd/log/modules_*.log 2>/dev/null \
    | grep -E ": *${pid}:" | grep 'Hooked ' | sed 's/.*] Hooked /Hooked /' | sort -u)
  if [ -n "$lines" ]; then
    echo "BRIDGE_HOOKS $process pid=$pid: registration evidence present"
    printf '%s\n' "$lines"
  else
    echo "BRIDGE_HOOKS $process pid=$pid: UNKNOWN (no current-PID log evidence)"
  fi
done
echo 'Registration evidence is not end-to-end push delivery proof.'
