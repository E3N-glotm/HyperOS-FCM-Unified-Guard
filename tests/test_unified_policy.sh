#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/run"
cat > "$T/bin/cmd" <<'MOCK'
#!/bin/sh
[ "$1 $2" = 'deviceidle whitelist' ] || exit 1
case "${3:-}" in
  '') cat "$MOCK_LIST" ;;
  +com.google.android.gms)
    printf 'user,com.google.android.gms,10139\n' >> "$MOCK_LIST" ;;
  -com.google.android.gms)
    grep -v '^user,com.google.android.gms,' "$MOCK_LIST" > "$MOCK_LIST.tmp"
    mv "$MOCK_LIST.tmp" "$MOCK_LIST" ;;
  *) exit 4 ;;
esac
MOCK
chmod +x "$T/bin/cmd"
export PATH="$T/bin:$PATH" FCM_UNIFIED_RUNTIME="$T/run" MOCK_LIST="$T/list"
SCRIPT="$ROOT/module/bin/deviceidle_policy.sh"
printf 'system,com.google.android.gms,10139\n' > "$T/list"
sh "$SCRIPT" status >/dev/null
sh "$SCRIPT" apply >/dev/null
[ ! -e "$T/run/deviceidle-owned.list" ] || exit 9
printf 'DEVICEIDLE_GMS_POLICY=enforce\n' > "$T/run/unified.conf"
sh "$SCRIPT" apply >/dev/null
[ ! -e "$T/run/deviceidle-owned.list" ] || exit 10
[ "$(wc -l < "$T/list")" -eq 1 ] || exit 11

: > "$T/list"
printf 'DEVICEIDLE_GMS_POLICY=observe\n' > "$T/run/unified.conf"
sh "$SCRIPT" apply >/dev/null
[ ! -e "$T/run/deviceidle-owned.list" ] || exit 12
[ ! -s "$T/list" ] || exit 13

printf 'DEVICEIDLE_GMS_POLICY=enforce\n' > "$T/run/unified.conf"
sh "$SCRIPT" apply >/dev/null
[ -f "$T/run/deviceidle-owned.list" ] || exit 14
grep -q '^user,com.google.android.gms,10139$' "$T/list" || exit 15
sh "$SCRIPT" restore
[ ! -e "$T/run/deviceidle-owned.list" ] || exit 16
[ ! -s "$T/list" ] || exit 17

grep -q 'CONFLICT: Millet Guard' "$ROOT/module/service.sh"
grep -q 'gms_millet_guard/disable' "$ROOT/module/service.sh"
grep -q '^id=fcm_unified_guard' "$ROOT/module/module.prop"
grep -q '/data/adb/fcm_unified_guard' "$ROOT/module/bin/lib.sh"
! grep -q '^RUNDIR=/data/adb/millet_guard' "$ROOT/module/bin/lib.sh"
echo 'PASS: native DeviceIdle observe, opt-in, ownership and conflict safety'
