#!/system/bin/sh
# Capability checks are shared by installation, early boot and diagnostics.
# No device, Android release or ROM-build allowlist is used here.
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
current_rom_identity() {
  # An installation snapshot detects OTA changes; none of these values are
  # compared with a release/build/device constant supplied by the project.
  for prop in ro.build.fingerprint ro.build.version.sdk ro.build.version.incremental \
      ro.system.build.fingerprint ro.system_ext.build.fingerprint \
      ro.product.build.fingerprint ro.vendor.build.fingerprint; do
    printf '%s=%s\n' "$prop" "$(getprop "$prop")"
  done | sha256sum | cut -d ' ' -f 1
}
find_art_vm() {
  for name in dalvikvm64 dalvikvm; do
    vm=$(command -v "$name" 2>/dev/null) || continue
    [ ! -x "$vm" ] || { printf '%s\n' "$vm"; return 0; }
  done
  for vm in /apex/com.android.art/bin/dalvikvm64 /apex/com.android.art/bin/dalvikvm \
      /system/bin/dalvikvm64 /system/bin/dalvikvm; do
    [ ! -x "$vm" ] || { printf '%s\n' "$vm"; return 0; }
  done
  return 1
}
discover_oem_jar() {
  # Optional arguments make path discovery independently testable. Normal
  # installation inspects the active classpath plus standard partition paths.
  if [ "$#" -eq 0 ]; then
    # Prefer files the running system actually loads; unused copies on other
    # partitions must not make an otherwise unambiguous classpath fail.
    set -- $(printf '%s' "${SYSTEMSERVERCLASSPATH:-}" | tr ':' ' ')
    active=0
    for candidate do
      case "$candidate" in */miui-services.jar) [ ! -r "$candidate" ] || active=1;; esac
    done
    if [ "$active" = 1 ]; then
      discover_oem_jar "$@"
      return $?
    fi
    set -- /system_ext/framework/miui-services.jar /system/framework/miui-services.jar \
      /product/framework/miui-services.jar
  fi
  selected=
  for candidate do
    case "$candidate" in */miui-services.jar) :;; *) continue;; esac
    [ -f "$candidate" ] && [ -r "$candidate" ] || continue
    canonical=$(readlink -f "$candidate") || return 1
    [ "$canonical" != "$selected" ] || continue
    [ -z "$selected" ] || { echo 'Ambiguous OEM framework paths' >&2; return 1; }
    selected=$canonical
  done
  [ -n "$selected" ] || return 1
  printf '%s\n' "$selected"
}
profile_valid() {
  [ "${PROFILE_FORMAT:-}" = 2 ] || return 1
  framework_path_ok "${SOURCE_SERVICES_PATH:-}" || return 1
  framework_path_ok "${SOURCE_MIUI_PATH:-}" || return 1
  [ "$SOURCE_SERVICES_PATH" != "$SOURCE_MIUI_PATH" ] || return 1
  for digest in "${SOURCE_SERVICES_SHA256:-}" "${SOURCE_MIUI_SHA256:-}" \
      "${PATCHED_SERVICES_SHA256:-}" "${PATCHED_MIUI_SHA256:-}" "${INSTALLED_ROM_SHA256:-}"; do
    valid_hash "$digest" || return 1
  done
}
