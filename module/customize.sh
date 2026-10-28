#!/system/bin/sh
# Magisk customize script. Keep persistent user configuration outside MODPATH
# so upgrades do not overwrite it.
RUNDIR=/data/adb/fcm_unified_guard
CONFIG=$RUNDIR/packages.list
mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<'LIST'
# Unified Guard managed packages, one Android package name per line.
# Blank lines and lines starting with # are ignored.
com.google.android.gms
LIST
  chmod 600 "$CONFIG"
fi
if [ ! -f "$RUNDIR/unified.conf" ]; then
  cat > "$RUNDIR/unified.conf" <<'CONF'
# Observe Android DeviceIdle by default; enforce is optional.
DEVICEIDLE_GMS_POLICY=observe
CONF
  chmod 600 "$RUNDIR/unified.conf"
fi
ui_print "- Unified Guard configuration: $CONFIG"
ui_print "- Default managed package: com.google.android.gms"
ui_print "- No LSPosed dependency; no equivalent system broadcast Hook"
ui_print "- Do not run together with the original Millet Guard"
ui_print "- Original modules remain installed and untouched"
ui_print "- Setting Unified Guard script permissions"
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/reconcile.sh" 0 0 0755
set_perm "$MODPATH/bin/inotify_handler.sh" 0 0 0755
set_perm "$MODPATH/bin/milletctl" 0 0 0755
set_perm "$MODPATH/bin/fcm_guard.sh" 0 0 0755
set_perm "$MODPATH/bin/fcm_event_worker.sh" 0 0 0755
set_perm "$MODPATH/bin/lib.sh" 0 0 0644
set_perm "$MODPATH/bin/deviceidle_policy.sh" 0 0 0755
