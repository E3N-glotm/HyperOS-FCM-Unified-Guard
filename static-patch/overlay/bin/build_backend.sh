#!/system/bin/sh
MODDIR=${0%/*}/..
MODDIR=$(cd "$MODDIR" && pwd)
. "$MODDIR/bin/static_common.sh"
B=$MODDIR/backend
mkdir -p "$B"
. "$MODDIR/bin/runtime_workers.sh"
if ! mkdir "$B/build.lock" 2>/dev/null; then
  if read -r owner_pid owner_ticks 2>/dev/null < "$B/build.lock/owner"; then
    [ "$(worker_ticks "$owner_pid")" != "$owner_ticks" ] || exit 0
  else
    lock_stamp=$(stat -c %Y "$B/build.lock" 2>/dev/null)
    lock_now=$(date +%s)
    case "$lock_stamp" in ''|*[!0-9]*) exit 0;; esac
    [ $((lock_now-lock_stamp)) -ge 30 ] || exit 0
  fi
  rm -f "$B/build.lock/owner"; rmdir "$B/build.lock" 2>/dev/null || exit 0
  mkdir "$B/build.lock" 2>/dev/null || exit 0
fi
printf '%s %s\n' "$$" "$(worker_ticks $$)" > "$B/build.lock/owner"
WORK=
cleanup_build() {
  build_rc=$?
  if [ "$build_rc" -ne 0 ] && grep -q '^BUILDING' "$B/state" 2>/dev/null; then
    backend_note ERROR "adaptation interrupted or file operation failed; base guard remains enabled"
  fi
  [ -z "$WORK" ] || rm -rf "$WORK"
  rm -f "$B/build.lock/owner"; rmdir "$B/build.lock" 2>/dev/null || true
}
trap cleanup_build EXIT
trap 'exit 1' HUP INT TERM
mode=${1:-auto}
[ "$mode" != retry ] || { rm -f "$B/quarantine" "$B/last-attempt" "$B/unsupported-key"; }
VM=$(find_art_vm) || { backend_note CORE_ONLY "ART VM unavailable; base guard remains active"; exit 0; }
policy_hash=$(hash_file "$MODDIR/tools/policy.dex")
generator_hash=$(hash_file "$MODDIR/tools/patcher.jar")
target_services=$(readlink -f /system/framework/services.jar)
target_oem=$(discover_oem_jar 2>/dev/null || true)
[ -z "$target_oem" ] || framework_path_ok "$target_oem" || target_oem=
framework_path_ok "$target_services" || { backend_note CORE_ONLY "Android services DEX unavailable; base guard remains active"; exit 0; }
input_services=$target_services
input_oem=$target_oem
loaded=0
if read -r mounted_boot mounted_slot 2>/dev/null < "$B/mounted" && [ "$mounted_boot" = "$(boot_id)" ]; then
  cache_load_slot "$mounted_slot" && loaded=1
fi
[ "$loaded" = 1 ] || { cache_load && loaded=1; }
if [ "$loaded" = 1 ] && cache_payload_ok; then
  if cache_mounted; then
    if [ "$POLICY_SHA256" = "$policy_hash" ] && [ "${GENERATOR_SHA256:-}" = "$generator_hash" ] && [ "$mode" != retry ] && cache_security_ok; then
      if [ "$(cat "$B/current" 2>/dev/null)" = "$generation" ]; then
        if [ -r "$B/pending" ]; then
          backend_note MOUNTED "framework mounted; waiting for boot acknowledgement; no further reboot needed"
        else backend_note ACTIVE "current backend verified; base guard remains active"; fi
      else backend_note READY "updated backend ready; next normal reboot activates it"; fi
      exit 0
    fi
    if [ -r "$CACHE_DIR/source/services.jar" ] && [ "$(hash_file "$CACHE_DIR/source/services.jar")" = "$SOURCE_SERVICES_SHA256" ]; then
      input_services=$CACHE_DIR/source/services.jar
      target_services=$SOURCE_SERVICES_PATH
      input_oem= target_oem=
      if [ -n "$SOURCE_MIUI_PATH" ] && [ "$(hash_file "$CACHE_DIR/source/miui-services.jar")" = "$SOURCE_MIUI_SHA256" ]; then
        input_oem=$CACHE_DIR/source/miui-services.jar; target_oem=$SOURCE_MIUI_PATH
      fi
    else
      if [ -r "$B/pending" ]; then
        backend_note MOUNTED "verified legacy framework mounted; waiting for boot acknowledgement; no further reboot needed"
      else backend_note ACTIVE "verified legacy backend retained; clean source will be captured after a system change"; fi
      exit 0
    fi
  elif cache_source_ok && [ "$(cat "$B/quarantine" 2>/dev/null)" = "$generation" ]; then
    backend_note QUARANTINED "previous backend boot unacknowledged; base core active; use Action to retry"
    exit 0
  fi
fi
source_hash=$(hash_file "$input_services")
oem_hash=
[ -z "$input_oem" ] || oem_hash=$(hash_file "$input_oem")
api_hash=$(hash_file /system/framework/framework.jar)
valid_hash "$source_hash" && valid_hash "$policy_hash" && valid_hash "$generator_hash" || {
  backend_note ERROR "cannot read current build inputs; base core remains enabled"; exit 1;
}
key=$(printf '%s\n' "$target_services" "$source_hash" "$target_oem" "$oem_hash" "$api_hash" "$policy_hash" "$generator_hash" | sha256sum | cut -d ' ' -f 1)
if [ "$mode" != retry ]; then
  if [ "$(cat "$B/unsupported-key" 2>/dev/null)" = "$key" ]; then
    backend_note CORE_ONLY "no static capabilities for these inputs; base guard active; change detected inputs or use Action to retry"
    exit 0
  fi
  if [ "$(cat "$B/last-attempt" 2>/dev/null)" = "$(boot_id):$key" ]; then exit 0; fi
  if cache_load && [ "${SOURCE_KEY:-}" = "$key" ] && cache_payload_ok && cache_security_ok; then
    backend_note READY "adapted cache ready; next normal reboot loads the new framework"
    exit 0
  fi
fi
printf '%s:%s\n' "$(boot_id)" "$key" > "$B/last-attempt"
backend_note BUILDING "detecting this system and generating supported features; base guard continues"
WORK=$B/.build.$$
mkdir -p "$WORK/source" "$WORK/patched" || exit 1
cp -p "$input_services" "$WORK/source/services.jar" || exit 1
if [ -n "$input_oem" ]; then cp -p "$input_oem" "$WORK/source/miui-services.jar" || exit 1; fi
oem_arg=-
[ -z "$input_oem" ] || oem_arg=$WORK/source/miui-services.jar
excluded=
attempt=0
verified=0
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt+1))
  rm -f "$WORK/patched/"*
  if ! CLASSPATH="$MODDIR/tools/patcher.jar" bounded "$VM" -Xmx1024m io.github.e3n.fcmu.Adaptive \
      "$WORK/source/services.jar" "$oem_arg" "$MODDIR/tools/policy.dex" "$WORK/patched" "$excluded" > "$B/build.log" 2>&1; then
    [ ! -f "$WORK/patched/capabilities.tsv" ] || cp "$WORK/patched/capabilities.tsv" "$B/last-capabilities.tsv"
    if [ -f "$WORK/patched/capabilities.tsv" ] && ! grep -q "$(printf '\t')ready$(printf '\t')" "$WORK/patched/capabilities.tsv"; then
      printf '%s\n' "$key" > "$B/unsupported-key"
      backend_note CORE_ONLY "no compatible static features; base guard active; see feature details"
      exit 0
    fi
    backend_note ERROR "framework generation failed; base guard active; see build.log"
    exit 1
  fi
  verify_jars=$WORK/patched/services.jar
  [ ! -f "$WORK/patched/miui-services.jar" ] || verify_jars="$verify_jars $WORK/patched/miui-services.jar"
  CLASSPATH="$MODDIR/tools/verify.jar" bounded "$VM" io.github.e3n.fcmu.Verify --jar $verify_jars >> "$B/build.log" 2>&1 || {
    backend_note ERROR "generated DEX alignment failed; base guard active"; exit 1;
  }
  if CLASSPATH="$MODDIR/tools/verify.jar:$WORK/patched/services.jar:$WORK/patched/miui-services.jar:${SYSTEMSERVERCLASSPATH:-}" \
      bounded "$VM" -Xmx512m -Xverify:all io.github.e3n.fcmu.Verify --adaptive "$WORK/patched/capabilities.tsv" > "$WORK/verify.log" 2>&1; then
    cat "$WORK/verify.log" >> "$B/build.log"; verified=1; break
  fi
  cat "$WORK/verify.log" >> "$B/build.log"
  failed=$(awk -F '\t' '$1=="VERIFY_FAIL" {if(out!="")out=out",";out=out $2} END {print out}' "$WORK/verify.log")
  [ -n "$failed" ] || break
  [ -z "$excluded" ] && excluded=$failed || excluded=$excluded,$failed
done
[ "$verified" = 1 ] || { backend_note ERROR "ART validation failed; base guard active; feature details in build.log"; exit 1; }
[ "$(hash_file "$input_services")" = "$source_hash" ] && { [ -z "$input_oem" ] || [ "$(hash_file "$input_oem")" = "$oem_hash" ]; } || {
  backend_note REBUILD "system changed during generation; retry automatically on next boot"; exit 1;
}
[ "$(hash_file /system/framework/framework.jar)" = "$api_hash" ] || { backend_note REBUILD "Android APIs changed during generation"; exit 1; }
if [ ! -f "$WORK/patched/miui-services.jar" ]; then target_oem=; oem_hash=; fi
{
  echo PROFILE_FORMAT=3
  echo "SOURCE_SERVICES_PATH=$target_services"
  echo "SOURCE_SERVICES_SHA256=$source_hash"
  echo "SOURCE_MIUI_PATH=$target_oem"
  echo "SOURCE_MIUI_SHA256=$oem_hash"
  echo "BASE_API_SHA256=$api_hash"
  echo "POLICY_SHA256=$policy_hash"
  echo "GENERATOR_SHA256=$generator_hash"
  echo "SOURCE_KEY=$key"
  echo "PATCHED_SERVICES_SHA256=$(hash_file "$WORK/patched/services.jar")"
  if [ -n "$target_oem" ]; then echo "PATCHED_MIUI_SHA256=$(hash_file "$WORK/patched/miui-services.jar")"; else echo PATCHED_MIUI_SHA256=; fi
} > "$WORK/profile.conf"
chcon u:object_r:system_file:s0 "$WORK/patched/"*.jar >> "$B/build.log" 2>&1 || {
  backend_note ERROR "framework security context rejected; base guard active"; exit 1;
}
if ! ( CACHE_DIR=$WORK; . "$WORK/profile.conf"; cache_profile_valid && cache_payload_ok && cache_security_ok ); then
  backend_note ERROR "generated cache identity/security validation failed; base guard active"
  exit 1
fi
cp "$WORK/patched/capabilities.tsv" "$WORK/capabilities.tsv"
next=generation-$(date +%s)-$$
mv "$WORK" "$B/$next" || exit 1
WORK=
printf '%s\n' "$next" > "$B/current.new"
mv -f "$B/current.new" "$B/current"
rm -f "$B/unsupported-key"
backend_note READY "supported framework features rebuilt automatically; next normal reboot activates them; no ZIP reinstall"
