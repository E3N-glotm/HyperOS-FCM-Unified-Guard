#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
export PATH="$T/bin:$PATH" SYSTEMSERVERCLASSPATH=
cat > "$T/bin/getprop" <<'SH'
#!/bin/sh
cat "$ROM_MARKER"
SH
cat > "$T/bin/chcon" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$T/bin/dalvikvm64" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -*) shift;; *) break;; esac
done
case "$1" in
 io.github.e3n.fcmu.Patcher)
  shift
  if [ "$1" = --probe ]; then
   [ "$SCENARIO" != missing-target ] || { echo 'missing capability fixture'; exit 8; }
   echo CAPABILITY_OK;exit 0
  fi
  [ "$SCENARIO" != generation-failure ] || exit 9
  printf 'generated-services\n' > "$4/services.jar"
  printf 'generated-oem\n' > "$4/miui-services.jar"
  [ "$SCENARIO" != changed-during-generation ] || echo changed-ROM > "$ROM_MARKER"
  ;;
 io.github.e3n.fcmu.Verify)
  [ "$SCENARIO" != art-rejection ] || exit 10
  echo VERIFIED;;
 *) exit 11;;
esac
SH
chmod +x "$T/bin/"*
for SCENARIO in arbitrary-ROM alternate-layout missing-target generation-failure art-rejection changed-during-generation; do
 export SCENARIO
 CASE_DIR="$T/$SCENARIO"
 mkdir -p "$CASE_DIR/system/framework" "$CASE_DIR/system_ext/framework" "$CASE_DIR/product/framework" "$CASE_DIR/module/bin"
 printf 'original-services\n' > "$CASE_DIR/system/framework/services.jar"
 OEM="$CASE_DIR/system_ext/framework/miui-services.jar"
 [ "$SCENARIO" != alternate-layout ] || OEM="$CASE_DIR/product/framework/miui-services.jar"
 printf 'original-oem\n' > "$OEM"
 export ROM_MARKER="$CASE_DIR/rom" MODPATH="$CASE_DIR/module" FCM_UNIFIED_RUNTIME="$CASE_DIR/runtime"
 echo arbitrary-vendor-and-future-release > "$ROM_MARKER"
 for src in customize.sh bin/static_common.sh; do
  sed -e "s@/system_ext/@$CASE_DIR/system_ext/@g" -e "s@/system/@$CASE_DIR/system/@g" \
      -e "s@/product/@$CASE_DIR/product/@g" -e "s@/data/adb/@$CASE_DIR/data/adb/@g" \
      "$ROOT/overlay/$src" > "$MODPATH/$src"
 done
 cat > "$CASE_DIR/install.sh" <<'SH'
#!/bin/sh
abort() { echo "ABORT: $*" >&2; exit 1; }
ui_print() { :; }
set_perm_recursive() { :; }
set_perm() { :; }
. "$MODPATH/customize.sh"
SH
 if sh "$CASE_DIR/install.sh" > "$CASE_DIR/result" 2>&1; then
  case "$SCENARIO" in arbitrary-ROM|alternate-layout) :;; *) cat "$CASE_DIR/result";exit 1;; esac
  . "$MODPATH/profile.conf"
  [ "$SOURCE_MIUI_PATH" = "$OEM" ]
  [ "$SOURCE_SERVICES_SHA256" = "$(sha256sum "$CASE_DIR/system/framework/services.jar" | cut -d ' ' -f 1)" ]
  [ "$SOURCE_MIUI_SHA256" = "$(sha256sum "$OEM" | cut -d ' ' -f 1)" ]
  [ -f "$MODPATH/patched/services.jar" ] && [ -f "$MODPATH/patched/miui-services.jar" ]
  grep -qx DEVICEIDLE_GMS_POLICY=enforce "$FCM_UNIFIED_RUNTIME/unified.conf"
 else
  case "$SCENARIO" in arbitrary-ROM|alternate-layout) cat "$CASE_DIR/result";exit 1;; esac
  [ ! -d "$MODPATH/patched" ] && [ ! -f "$FCM_UNIFIED_RUNTIME/unified.conf" ]
 fi
 grep -qx original-services "$CASE_DIR/system/framework/services.jar"
 grep -qx original-oem "$OEM"
done
echo 'PASS installer flow: arbitrary ROM and alternate layout accepted; missing target/generation/ART/ROM-race failures reject before acceptance'
