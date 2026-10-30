#!/system/bin/sh
# On-demand OEM process discovery. Only called from Magisk Action; never run
# on the 2/5-minute FCM maintenance cycles. Absence is not fatal.
MODDIR=$(cd "$(dirname "$0")/.." && pwd)
B="$MODDIR/backend"
mkdir -p "$B" || exit 0
tmp="$B/.powerkeeper-processes.$$"
: > "$tmp"
pm list packages -f 2>/dev/null |
  grep -i 'powerkeeper' |
  sed -n 's/^package:.*=//p' |
  while IFS= read -r pkg; do
    case "$pkg" in
      ''|*[!A-Za-z0-9_.$]*) continue;;
    esac
    [ "${#pkg}" -le 128 ] || continue
    printf '%s\n' "$pkg"
  done | sort -u > "$tmp"
# Preserve the previous proven process list if PackageManager is temporarily
# unavailable; never erase it based on an empty/failed shell probe.
if [ -s "$tmp" ]; then mv -f "$tmp" "$B/powerkeeper-packages.list"
else rm -f "$tmp"; fi
exit 0
