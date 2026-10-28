#!/system/bin/sh
# Optional explicit migration. Never enumerate or signal unrelated processes.
# Does not install/disable LSPosed, reset GMS, or reboot the device.
set -eu
OLD=/data/adb/modules/gms_millet_guard
NEW=/data/adb/modules/fcm_unified_guard
STAGE=/data/adb/modules_update/fcm_unified_guard
RUN=/data/adb/fcm_unified_guard
BACK=$RUN/backups/pre-v020

fail() { echo "Migration refused: $*" >&2; exit 1; }

[ -r "$STAGE/module.prop" ] || fail 'staged Magisk package missing'
grep -q '^version=0.2.0$' "$STAGE/module.prop" ||
  fail 'unexpected staged version'
[ -r "$BACK/millet-runtime/packages.list" ] ||
  fail 'original package-list backup missing'
[ -r "$BACK/millet-runtime/managed.last" ] ||
  fail 'original ownership backup missing'
[ -e "$OLD/disable" ] ||
  fail 'disable the original module before migrating'
[ -r "$STAGE/bin/bridge_status.sh" ] ||
  fail 'integrated bridge status script missing'

# Do not duplicate running GMS broadcast hooks with an unverified APK.
sh "$STAGE/bin/bridge_status.sh" > "$RUN/bridge-before-migration.txt" ||
  fail 'bridge check failed'
grep -q '^BRIDGE_BINARY: verified' "$RUN/bridge-before-migration.txt" ||
  fail 'bridge binary differs from verified baseline'
grep -q 'BRIDGE_HOOKS system_server .*registration evidence present' "$RUN/bridge-before-migration.txt" ||
  fail 'no current system_server hook evidence'
grep -q 'BRIDGE_HOOKS com.miui.powerkeeper .*registration evidence present' "$RUN/bridge-before-migration.txt" ||
  fail 'no current PowerKeeper hook evidence'

for script in "$STAGE"/*.sh "$STAGE"/bin/*.sh; do
  sh -n "$script" || fail "syntax: $script"
done

# Validate all five *specific* old worker identities before touching any PID.
# NEVER walk parent process trees here: an earlier script accidentally
# included PID 1 and unrelated system services in its candidate list.
WORKERS='inotifyd safety fcm fcm_event swipe_unstop'
for name in $WORKERS; do
  f="/data/adb/millet_guard/$name.pid"
  [ -f "$f" ] || continue
  pid=$(cat "$f") || fail "cannot read $name PID"
  case "$pid" in ''|*[!0-9]*) fail "invalid $name PID";; esac
  [ "$pid" -gt 2 ] || fail "dangerous $name PID"
  actual=$(ps -A -o PID,ARGS | awk -v target="$pid" '$1==target {$1="";print;exit}')
  case "$actual" in
    '') ;; # stale pid
    *"$OLD"/service.sh*|*"$OLD"/bin/*)
      echo "Verified original worker $name pid=$pid" ;;
    *) fail "old worker pid=$pid has different command; refusing all signals" ;;
  esac
done

# Preserve known-good configuration and backoff state without importing
# locks or process identifiers from the previous implementation.
cp -p "$BACK/millet-runtime/packages.list" "$RUN/packages.list"
cp -p "$BACK/millet-runtime/managed.last" "$RUN/managed.last"
for name in fcm_keepalive.epoch fcm_recover.epoch fcm_recover.attempts \
  fcm_down_since.epoch fcm_soft_reconnect.epoch fcm_dns_fail.epoch \
  fcm_dns_flush.epoch fcm_bypass.uid; do
  [ ! -f "/data/adb/millet_guard/$name" ] ||
    cp -p "/data/adb/millet_guard/$name" "$RUN/$name"
done

cp -a "$STAGE/." "$NEW/"
rm -f "$STAGE/disable" "$NEW/disable"
chmod 755 "$NEW"/*.sh "$NEW"/bin/*.sh "$NEW"/bin/milletctl "$NEW"/bin/bridgectl

# Only signal a worker if its command still identifies the same original
# module. Do not use PID lists from previous runs or descendants of PID 1.
for name in $WORKERS; do
  f="/data/adb/millet_guard/$name.pid"
  [ -f "$f" ] || continue
  pid=$(cat "$f") || continue
  actual=$(ps -A -o PID,ARGS | awk -v target="$pid" '$1==target {$1="";print;exit}')
  case "$actual" in
    *"$OLD"/service.sh*|*"$OLD"/bin/*)
      kill -CONT "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true ;;
  esac
done

nohup sh "$NEW/service.sh" > "$RUN/migration-start.log" 2>&1 < /dev/null &
echo 'Migration started. Verify the three new worker PID identities and GcmService.'
