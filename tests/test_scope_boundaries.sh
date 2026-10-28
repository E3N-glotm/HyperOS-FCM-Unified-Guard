#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FCM_WORKER="$ROOT/module/bin/fcm_event_worker.sh"
SWIPE_WORKER="$ROOT/module/bin/swipe_unstop_worker.sh"
CTL="$ROOT/module/bin/milletctl"
SERVICE="$ROOT/module/service.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$SWIPE_WORKER" ] || fail "SwipeUpClean worker is missing"
grep -q "logcat -b events" "$SWIPE_WORKER" || fail "SwipeUpClean worker must read ActivityManager events"
grep -q "due to SwipeUpClean" "$SWIPE_WORKER" || fail "SwipeUpClean reason filter is missing"
grep -q "grep -Fxq.*CONFIG" "$SWIPE_WORKER" || fail "SwipeUpClean worker must be limited to managed packages"
grep -q 'cmd package unstop --user 0' "$SWIPE_WORKER" || fail "worker must use narrow package unstop"
if grep -qE 'am start|monkey|setPackageStoppedState|force-stop' "$SWIPE_WORKER"; then
  fail "SwipeUpClean worker must not relaunch apps, force-stop them, or use hidden binder transactions"
fi

grep -q "swipe_unstop_worker.sh" "$SERVICE" || fail "service does not launch SwipeUpClean worker"
grep -q "swipe_unstop.pid" "$SERVICE" || fail "service does not track SwipeUpClean worker"
grep -q "reconcile.sh.*ctl-apply" "$CTL" || fail "milletctl apply must invoke reconcile.sh"

grep -q -- "--regex='sourcePkg=com.google.android.gms'" "$FCM_WORKER" \
  || fail "FCM event worker must stay scoped to GMS alarm events"
grep -q "logcat -b main" "$FCM_WORKER" \
  || fail "FCM event worker must observe the existing Whetstone main-buffer path"

echo "Module scope regression checks passed"
