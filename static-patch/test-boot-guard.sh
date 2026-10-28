#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/getprop" <<'SH'
#!/bin/sh
case "$1" in
 ro.product.device) echo pudding;;
 ro.build.version.sdk) echo 37;;
 ro.build.version.incremental) if [ "$SCENARIO" = ota ]; then echo updated; else echo OS4.0.5.0.XPCCNXM; fi;;
esac
SH
cat > "$TMP/bin/sha256sum" <<'SH'
#!/bin/sh
case "$1" in
 */patched/services.jar) echo "new-services  $1";;
 */patched/miui-services.jar) echo "new-miui  $1";;
 /system/framework/services.jar)
  if [ "$SCENARIO" = hash ]; then echo bad; else echo "30807e80ec96a495b26aa13498abc9929cc4581666beacf33e234ae14532a1ac  $1"; fi;;
 *) echo "cf33fc7d00f73920e8ce4447022aedc1de0faa024a4be351cccbaf39c8376aab  $1";;
esac
SH
cat > "$TMP/bin/mount" <<'SH'
#!/bin/sh
echo "mount $*" >> "$CALLS"
case "$SCENARIO:$*" in partial:*miui-services.jar*) exit 1;;esac
SH
cat > "$TMP/bin/umount" <<'SH'
#!/bin/sh
echo "umount $*" >> "$CALLS"
SH
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
for SCENARIO in success ota hash pending partial; do
 export SCENARIO CALLS="$TMP/$SCENARIO.calls"
 MOD="$TMP/$SCENARIO";mkdir -p "$MOD/patched"
 cp "$ROOT/overlay/post-fs-data.sh" "$MOD/"
 cp "$ROOT/overlay/profile.conf" "$MOD/"
 printf '%s\n' PATCHED_SERVICES_SHA256=new-services PATCHED_MIUI_SHA256=new-miui >> "$MOD/profile.conf"
 : > "$CALLS"
 [ "$SCENARIO" != pending ] || touch "$MOD/static-boot-pending"
 sh "$MOD/post-fs-data.sh"
 case "$SCENARIO" in
 success)
  test -f "$MOD/static-boot-pending";test ! -f "$MOD/disable"
  test "$(wc -l < "$CALLS")" -eq 2;;
 partial)
  test -f "$MOD/disable";test ! -f "$MOD/static-boot-pending"
  grep -q '^umount /system/framework/services.jar$' "$CALLS";;
 *)
  test -f "$MOD/disable";test ! -s "$CALLS";test ! -f "$MOD/static-boot-pending";;
 esac
done
echo 'PASS boot guard: successful mounts, OTA mismatch, hash mismatch, incomplete previous boot, partial mount rollback'
