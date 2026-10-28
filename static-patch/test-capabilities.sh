#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
. "$ROOT/overlay/bin/static_common.sh"
mkdir -p "$T/a" "$T/b" "$T/alias"
: > "$T/a/miui-services.jar"
ln -s "$T/a/miui-services.jar" "$T/alias/miui-services.jar"
test "$(discover_oem_jar "$T/missing/miui-services.jar" "$T/a/miui-services.jar")" = "$(readlink -f "$T/a/miui-services.jar")"
if [ -L "$T/alias/miui-services.jar" ]; then
 test "$(discover_oem_jar "$T/a/miui-services.jar" "$T/alias/miui-services.jar")" = "$(readlink -f "$T/a/miui-services.jar")"
else
 echo 'SKIP symlink alias on hosts whose ln copies files; Linux CI covers real aliases'
fi
! discover_oem_jar "$T/missing/miui-services.jar"
: > "$T/b/miui-services.jar"
! discover_oem_jar "$T/a/miui-services.jar" "$T/b/miui-services.jar" 2>/dev/null
test "$(SYSTEMSERVERCLASSPATH="$T/a/miui-services.jar" discover_oem_jar)" = "$(readlink -f "$T/a/miui-services.jar")"
! SYSTEMSERVERCLASSPATH="$T/a/miui-services.jar:$T/b/miui-services.jar" discover_oem_jar 2>/dev/null
framework_path_ok /system/framework/miui-services.jar
framework_path_ok /system_ext/framework/miui-services.jar
framework_path_ok /product/framework/miui-services.jar
! framework_path_ok /data/local/tmp/miui-services.jar
valid_hash "$(printf '%064d' 1)"
! valid_hash ''
! valid_hash "$(printf '%064d' 1)g"
PROFILE_FORMAT=2
SOURCE_SERVICES_PATH=/system/framework/services.jar
SOURCE_MIUI_PATH=/product/framework/miui-services.jar
SOURCE_SERVICES_SHA256=$(printf '%064d' 1)
SOURCE_MIUI_SHA256=$(printf '%064d' 2)
PATCHED_SERVICES_SHA256=$(printf '%064d' 3)
PATCHED_MIUI_SHA256=$(printf '%064d' 4)
INSTALLED_ROM_SHA256=$(printf '%064d' 5)
profile_valid
PATCHED_MIUI_SHA256=
! profile_valid
echo 'PASS capability helpers: discovered/alias/missing/ambiguous framework paths and complete generated profile'
