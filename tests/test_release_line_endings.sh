#!/usr/bin/env bash
set -euo pipefail

ZIP=${1:-}
[ -n "$ZIP" ] && [ -f "$ZIP" ] || {
  echo "FAIL: release zip path is required" >&2
  exit 1
}

files=(
  action.sh
  customize.sh
  service.sh
  uninstall.sh
  module.prop
  bin/fcm_event_worker.sh
  bin/fcm_guard.sh
  bin/inotify_handler.sh
  bin/lib.sh
  bin/milletctl
  bin/reconcile.sh
  bin/swipe_unstop_worker.sh
)

for file in "${files[@]}"; do
  if unzip -p "$ZIP" "$file" | grep -q $'\r'; then
    echo "FAIL: CRLF/CR found in packaged $file" >&2
    exit 1
  fi
done

echo "release line-ending regression: PASS"
