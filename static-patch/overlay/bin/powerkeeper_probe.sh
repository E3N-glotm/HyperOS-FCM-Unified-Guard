#!/system/bin/sh
# Read-only, on-demand PowerKeeper DEX audit. No model/version gate, no daemon.
MODDIR=$(cd "$(dirname "$0")/.." && pwd)
. "$MODDIR/bin/static_common.sh"
B=$MODDIR/backend
mkdir -p "$B" || exit 0
out=$B/powerkeeper-capabilities.tsv
tmp=$B/.powerkeeper-probe.$$.tsv
apk_list=
for pkg in com.miui.powerkeeper com.xiaomi.powerkeeper; do
  paths=$(pm path "$pkg" 2>/dev/null || true)
  apk_list="$apk_list
$paths"
done
apk_list="$apk_list
$(pm list packages -f 2>/dev/null | grep -i powerkeeper | sed -n 's/^package:\(.*\.apk\)=.*$/package:\1/p' || true)"
set --
while IFS= read -r line; do
  case "$line" in package:/*.apk) candidate=$(printf '%s' "$line" | sed 's/^package://');; *) continue;; esac
  [ -r "$candidate" ] || continue
  duplicate=0
  for old in "$@"; do [ "$old" != "$candidate" ] || duplicate=1; done
  [ "$duplicate" = 0 ] || continue
  [ "$#" -lt 12 ] || break
  set -- "$@" "$candidate"
done <<EOF
$apk_list
EOF
if [ "$#" -eq 0 ]; then
  printf 'pk.apk\tunknown\tNo PowerKeeper APK found; FCM core independent\npk.equivalence\tunverified\tNo Hook activated\n' > "$tmp"
elif ! VM=$(find_art_vm) || [ ! -r "$MODDIR/tools/patcher.jar" ]; then
  printf 'pk.apk\tunknown\tART VM or probe unavailable; FCM core independent\npk.equivalence\tunverified\tNo Hook activated\n' > "$tmp"
else
  if ! CLASSPATH="$MODDIR/tools/patcher.jar" bounded "$VM" -Xmx512m io.github.e3n.fcmu.PowerKeeperProbe "$@" > "$tmp" 2>"$B/powerkeeper-probe.log"; then
    printf 'pk.apk\tunknown\tProbe failed; see powerkeeper-probe.log; FCM core independent\npk.equivalence\tunverified\tNo Hook activated\n' > "$tmp"
  fi
fi
if [ -s "$tmp" ]; then mv -f "$tmp" "$out"; else rm -f "$tmp"; fi
cat "$out"
exit 0
