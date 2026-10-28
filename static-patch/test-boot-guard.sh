#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export REAL_SHA
REAL_SHA=$(command -v sha256sum)
cat > "$TMP/bin/getprop" <<'SH'
#!/bin/sh
case "$1" in
 ro.build.fingerprint)
  if [ "$SCENARIO" = ota ]; then echo changed-firmware; else echo arbitrary-firmware; fi;;
 ro.build.version.sdk) echo "$MOCK_SDK";;
 ro.product.device) echo any-model;;
 *) echo arbitrary-property;;
esac
SH
cat > "$TMP/bin/sha256sum" <<'SH'
#!/bin/sh
[ "$#" -gt 0 ] || exec "$REAL_SHA"
case "$1" in
 */patched/services.jar)
  if [ "$SCENARIO" = corrupt ]; then printf '%064d' 5; else printf '%064d' 3; fi;;
 */patched/miui-services.jar) printf '%064d' 4;;
 /system/framework/services.jar)
  if [ "$SCENARIO" = hash ]; then printf '%064d' 5; else printf '%064d' 1; fi;;
 */framework/miui-services.jar) printf '%064d' 2;;
 *) exit 3;;
esac
printf '  %s\n' "$1"
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
for SCENARIO in success alternate-layout arbitrary-release ota hash pending partial corrupt profile missing-profile; do
 export SCENARIO CALLS="$TMP/$SCENARIO.calls" MOCK_SDK=123
 [ "$SCENARIO" != arbitrary-release ] || export MOCK_SDK=987
 MOD="$TMP/$SCENARIO";mkdir -p "$MOD/patched" "$MOD/bin"
 cp "$ROOT/overlay/post-fs-data.sh" "$MOD/"
 cp "$ROOT/overlay/bin/static_common.sh" "$MOD/bin/"
 . "$MOD/bin/static_common.sh"
 OEM_PATH=/system_ext/framework/miui-services.jar
 [ "$SCENARIO" != alternate-layout ] || OEM_PATH=/system/framework/miui-services.jar
 {
  echo PROFILE_FORMAT=2
  echo SOURCE_SERVICES_PATH=/system/framework/services.jar
  echo "SOURCE_MIUI_PATH=$OEM_PATH"
  printf 'SOURCE_SERVICES_SHA256=%064d\n' 1
  printf 'SOURCE_MIUI_SHA256=%064d\n' 2
  printf 'PATCHED_SERVICES_SHA256=%064d\n' 3
  printf 'PATCHED_MIUI_SHA256=%064d\n' 4
  echo "INSTALLED_ROM_SHA256=$(SCENARIO=success current_rom_identity)"
 } > "$MOD/profile.conf"
 [ "$SCENARIO" != profile ] || sed -i 's@SOURCE_MIUI_PATH=.*@SOURCE_MIUI_PATH=/data/local/tmp/not-a-framework.jar@' "$MOD/profile.conf"
 [ "$SCENARIO" != missing-profile ] || rm "$MOD/profile.conf"
 : > "$CALLS"
 [ "$SCENARIO" != pending ] || touch "$MOD/static-boot-pending"
 sh "$MOD/post-fs-data.sh"
 case "$SCENARIO" in
 success|alternate-layout|arbitrary-release)
  test -f "$MOD/static-boot-pending";test ! -f "$MOD/disable"
  test "$(wc -l < "$CALLS")" -eq 2
  grep -q " $OEM_PATH$" "$CALLS";;
 partial)
  test -f "$MOD/disable";test ! -f "$MOD/static-boot-pending"
  grep -q '^umount /system/framework/services.jar$' "$CALLS";;
 *)
  test -f "$MOD/disable";test ! -s "$CALLS";test ! -f "$MOD/static-boot-pending";;
 esac
done
echo 'PASS boot guard: 10 scenarios including arbitrary identity, alternate paths, OTA, source/payload corruption and rollback'
