#!/system/bin/sh
MODDIR=${0%/*}
RUNDIR=/data/adb/fcm_unified_guard
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" restore >/dev/null 2>&1 || true
# The bridge may predate this module. Never uninstall it or edit LSPosed scope.
/system/bin/sh "$MODDIR/bin/runtime_workers.sh" stop
# Remove only entries last owned by this module, preserving every unrelated
# system/user/other-module entry.
OWNED=$RUNDIR/managed.last
cur=$(settings --user 0 get system MILLET_NO_RESTRICT_APP 2>/dev/null)
[ "$cur" = "null" ] && cur=""
if [ -f "$OWNED" ]; then
  new=$(printf '%s' "$cur" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' \
    | while IFS= read -r pkg; do grep -Fxq "$pkg" "$OWNED" 2>/dev/null || printf '%s\n' "$pkg"; done \
    | awk '!seen[$0]++ { if (out!="") out=out ", "; out=out $0 } END { print out }')
  if [ -n "$new" ]; then
    settings --user 0 put system MILLET_NO_RESTRICT_APP "$new" >/dev/null 2>&1
  else
    settings --user 0 delete system MILLET_NO_RESTRICT_APP >/dev/null 2>&1
  fi
fi
# Keep packages.list by default so reinstalling preserves user choices.
# Users who want a full purge can remove /data/adb/fcm_unified_guard manually.
rm -f "$RUNDIR/inotifyd.pid" "$RUNDIR/safety.pid" "$RUNDIR/fcm.pid" \
      "$RUNDIR/fcm_event.pid" "$RUNDIR/swipe_unstop.pid" "$RUNDIR/managed.last" \
      "$RUNDIR/system_server.pid" "$RUNDIR/limiter_check.epoch" \
      "$RUNDIR/fcm_keepalive.epoch" 2>/dev/null
