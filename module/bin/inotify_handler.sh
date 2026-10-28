#!/system/bin/sh
MODDIR=${0%/*}/..
events=$1
watched=$2
sub=$3
case "$sub" in
  settings_system.xml|settings_system.xml.fallback|settings_system.xml.*|"")
    sleep 1
    /system/bin/sh "$MODDIR/bin/reconcile.sh" "inotify:$events:$sub"
    ;;
esac
