#!/system/bin/sh
hash_file() { sha256sum "$1" 2>/dev/null | cut -d ' ' -f 1; }
valid_hash() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*) return 1;; esac
}
framework_path_ok() {
  case "$1" in
    /system/framework/*.jar|/system_ext/framework/*.jar|/product/framework/*.jar|/system/system_ext/framework/*.jar|/system/product/framework/*.jar) return 0;;
  esac
  return 1
}
find_art_vm() {
  for name in dalvikvm64 dalvikvm; do
    vm=$(command -v "$name" 2>/dev/null) || continue
    [ ! -x "$vm" ] || { printf '%s\n' "$vm"; return 0; }
  done
  for vm in /apex/com.android.art/bin/dalvikvm64 /apex/com.android.art/bin/dalvikvm /system/bin/dalvikvm64 /system/bin/dalvikvm; do
    [ ! -x "$vm" ] || { printf '%s\n' "$vm"; return 0; }
  done
  return 1
}
discover_oem_jar() {
  if [ "$#" -eq 0 ]; then
    set -- $(printf '%s' "${SYSTEMSERVERCLASSPATH:-}" | tr ':' ' ')
    active=0
    for candidate do
      case "$candidate" in */miui-services.jar) [ ! -r "$candidate" ] || active=1;; esac
    done
    if [ "$active" = 1 ]; then discover_oem_jar "$@"; return $?; fi
    set -- /system_ext/framework/miui-services.jar /system/framework/miui-services.jar /product/framework/miui-services.jar
  fi
  selected=
  for candidate do
    case "$candidate" in */miui-services.jar) :;; *) continue;; esac
    [ -f "$candidate" ] && [ -r "$candidate" ] || continue
    canonical=$(readlink -f "$candidate") || return 1
    [ "$canonical" != "$selected" ] || continue
    [ -z "$selected" ] || return 1
    selected=$canonical
  done
  [ -n "$selected" ] || return 1
  printf '%s\n' "$selected"
}
boot_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null || cat /proc/uptime
}
cache_profile_valid() {
  [ "${PROFILE_FORMAT:-}" = 3 ] || return 1
  framework_path_ok "${SOURCE_SERVICES_PATH:-}" || return 1
  for digest in "${SOURCE_SERVICES_SHA256:-}" "${PATCHED_SERVICES_SHA256:-}" "${POLICY_SHA256:-}"; do valid_hash "$digest" || return 1; done
  if [ -n "${SOURCE_MIUI_PATH:-}" ]; then
    framework_path_ok "$SOURCE_MIUI_PATH" || return 1
    [ "$SOURCE_SERVICES_PATH" != "$SOURCE_MIUI_PATH" ] || return 1
    valid_hash "${SOURCE_MIUI_SHA256:-}" && valid_hash "${PATCHED_MIUI_SHA256:-}" || return 1
  fi
}
cache_load() {
  [ -r "$MODDIR/backend/current" ] || return 1
  IFS= read -r generation < "$MODDIR/backend/current"
  cache_load_slot "$generation"
}
cache_load_slot() {
  generation=$1
  case "$generation" in generation-[0-9]*|legacy-[0-9]*) :;; *) return 1;; esac
  case "$generation" in *[!A-Za-z0-9._-]*) return 1;; esac
  CACHE_DIR=$MODDIR/backend/$generation
  [ -r "$CACHE_DIR/profile.conf" ] || return 1
  SOURCE_MIUI_PATH= SOURCE_MIUI_SHA256= PATCHED_MIUI_SHA256= BASE_API_SHA256=
  . "$CACHE_DIR/profile.conf"
  cache_profile_valid
}
cache_payload_ok() {
  [ "$(hash_file "$CACHE_DIR/patched/services.jar")" = "$PATCHED_SERVICES_SHA256" ] || return 1
  if [ -n "$SOURCE_MIUI_PATH" ]; then
    [ "$(hash_file "$CACHE_DIR/patched/miui-services.jar")" = "$PATCHED_MIUI_SHA256" ] || return 1
  fi
}
cache_security_ok() {
  command -v getenforce >/dev/null 2>&1 || return 0
  [ "$(getenforce 2>/dev/null)" = Enforcing ] || return 0
  ls -Zd "$CACHE_DIR/patched/services.jar" 2>/dev/null | grep -q 'u:object_r:system_file:s0' || return 1
  [ -z "$SOURCE_MIUI_PATH" ] || ls -Zd "$CACHE_DIR/patched/miui-services.jar" 2>/dev/null | grep -q 'u:object_r:system_file:s0'
}
cache_source_ok() {
  [ "$(hash_file "$SOURCE_SERVICES_PATH")" = "$SOURCE_SERVICES_SHA256" ] || return 1
  if [ -n "$SOURCE_MIUI_PATH" ]; then
    [ "$(hash_file "$SOURCE_MIUI_PATH")" = "$SOURCE_MIUI_SHA256" ] || return 1
  fi
  [ -z "$BASE_API_SHA256" ] || [ "$(hash_file /system/framework/framework.jar)" = "$BASE_API_SHA256" ] || return 1
  [ "$(hash_file "$MODDIR/tools/policy.dex")" = "$POLICY_SHA256" ]
}
cache_mounted() {
  [ "$(hash_file "$SOURCE_SERVICES_PATH")" = "$PATCHED_SERVICES_SHA256" ] || return 1
  [ -z "$SOURCE_MIUI_PATH" ] || [ "$(hash_file "$SOURCE_MIUI_PATH")" = "$PATCHED_MIUI_SHA256" ]
}
module_status_write() {
  mstatus_lamp=$1 mstatus_summary=$2
  [ -r "$MODDIR/module.prop" ] || return 0
  grep -Fqx "description=$mstatus_summary" "$MODDIR/module.prop" && return 0
  mstatus_tmp=$MODDIR/.module.prop.$$
  sed '/^description=/d;/^name=/d' "$MODDIR/module.prop" > "$mstatus_tmp" || return 0
  printf 'name=HyperOS FCM Unified Guard %s\ndescription=%s\n' "$mstatus_lamp" "$mstatus_summary" >> "$mstatus_tmp"
  chmod 644 "$mstatus_tmp"
  mv -f "$mstatus_tmp" "$MODDIR/module.prop" || true
}
backend_phase_label() {
  case "$1" in
    CHECKING) echo '正在检查本次启动，无需再次重启';;
    MOUNTED) echo '框架已挂载，正在确认启动，无需再次重启';;
    ACTIVE) echo '框架已加载';;
    READY) echo '待重启生效';;
    BUILDING) echo '自动适配中，请稍候';;
    REBUILD) echo '等待自动重建';;
    CORE_ONLY) echo '基础模式';;
    QUARANTINED) echo '框架需检查';;
    ERROR) echo '适配异常';;
    *) echo '等待自动适配';;
  esac
}
backend_publish_status() {
  # Publish the boot phase without dumpsys, hashing or starting another worker.
  # A completed bind mount is not yet an acknowledged Android boot or FCM check.
  case "$1" in ERROR|QUARANTINED) bstatus_lamp='🔴';; *) bstatus_lamp='🟡';; esac
  bstatus_summary="$bstatus_lamp $(backend_phase_label "$1")"
  [ "$1" != ACTIVE ] || bstatus_summary="$bstatus_summary | 守护与FCM检查中"
  module_status_write "$bstatus_lamp" "$bstatus_summary"
}
backend_read_state() {
  phase=CHECKING detail='checking current boot; previous boot status is not actionable' state_boot=
  if [ -r "$MODDIR/backend/state" ]; then
    IFS="$(printf '\t')" read -r phase detail state_boot < "$MODDIR/backend/state" || true
  fi
  if [ "$state_boot" != "$(boot_id)" ]; then
    phase=CHECKING detail='checking current boot; previous boot status is not actionable'
  fi
}
backend_note() {
  mkdir -p "$MODDIR/backend"
  printf '%s\t%s\t%s\n' "$1" "$2" "$(boot_id)" > "$MODDIR/backend/state.$$"
  mv -f "$MODDIR/backend/state.$$" "$MODDIR/backend/state" || return 1
  backend_publish_status "$1"
}
bounded() {
  if [ -x /data/adb/magisk/busybox ]; then /data/adb/magisk/busybox timeout 180 "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout 180 "$@"
  else "$@"; fi
}
