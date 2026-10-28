#!/system/bin/sh
MODDIR=${0%/*}/..

# `--regex` is present on the validated Android 16 logcat. On older builds,
# exit cleanly and let the independent two-minute fallback do the work instead
# of repeatedly spawning an unsupported logcat command.
logcat --help 2>&1 | grep -q -- '--regex' || exit 0

# HyperOS Whetstone reports AlarmManager deliveries in logcat. GMS already owns
# allow-while-idle wakeup alarms for its push stack, so observing those events
# lets Millet Guard re-check FCM while the device is naturally awake without
# adding a new AlarmManager timer or wakelock of its own.
while true; do
  logcat -b main -v brief -T 1 --regex='sourcePkg=com.google.android.gms' \
    -s whetstone.activity:I '*:S' 2>/dev/null \
  | while IFS= read -r _line; do
      /system/bin/sh "$MODDIR/bin/fcm_guard.sh" alarm-event >/dev/null 2>&1 || true
    done
  # If logcat is restarted/rotated, retry quietly instead of hot-looping.
  sleep 5
done
