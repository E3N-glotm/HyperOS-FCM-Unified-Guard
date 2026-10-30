#!/bin/sh
# Host regression: a vendor logcat without --regex must NOT make the
# events worker exit, and the fallback must remain tag-scoped.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module/bin" "$T/run" "$T/bin"
sed -e "s@RUNDIR=/data/adb/fcm_unified_guard@RUNDIR=$T/run@" \
    -e 's@/system/bin/sh@/bin/sh@g' \
    "$ROOT/module/bin/unified_event_worker.sh" > "$T/module/bin/unified_event_worker.sh"
sed -e "s@RUNDIR=\${FCM_UNIFIED_RUNTIME:-/data/adb/fcm_unified_guard}@RUNDIR=$T/run@" \
    "$ROOT/module/bin/runtime_workers.sh" > "$T/module/bin/runtime_workers.sh"
cat > "$T/bin/logcat" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = --help ]; then
  if [ "$MOCK_REGEX" = supported ]; then echo '--regex'; else echo 'logcat: tag,priority'; fi
  exit 0
fi
printf '%s\n' "$*" >> "$MOCK_CAPTURE"
printf '%s\n' 'I/whetstone.activity: sourcePkg=com.example.other'
sleep 8
MOCK
chmod +x "$T/bin/logcat"
: > "$T/run/packages.list"
for mode in missing supported; do
  export MOCK_REGEX="$mode" MOCK_CAPTURE="$T/$mode.args"
  # timeout terminates the parent after proving the event worker stayed
  # resident long enough to create its FIFO and launch the producer.
  rc=0
  PATH="$T/bin:$PATH" timeout 3 /bin/sh "$T/module/bin/unified_event_worker.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 124 ] || { echo "worker exited early with mode=$mode rc=$rc" >&2; exit 1; }
  [ -s "$MOCK_CAPTURE" ] || { echo "logcat producer never started for $mode" >&2; exit 1; }
  grep -Fq -- '-s whetstone.activity:I am_kill:I' "$MOCK_CAPTURE"
  if [ "$mode" = missing ]; then
    grep -q 'tag-only compatibility fallback' "$T/run/events-worker.mode"
    if grep -Fq -- '--regex=' "$MOCK_CAPTURE"; then
      echo 'Unsupported regex flag sent to OEM logcat' >&2; exit 1
    fi
  else
    grep -Fq -- '--regex=' "$MOCK_CAPTURE"
    grep -q 'regex + tag filtering' "$T/run/events-worker.mode"
  fi
done
echo 'PASS: OEM logcat fallback stays resident and tag-scoped; modern regex unchanged'
