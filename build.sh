#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"
VERSION=$(awk -F= '$1=="version" {print $2}' "$ROOT/module/module.prop")
ZIP="$OUT/HyperOS-FCM-Unified-Guard-v${VERSION}.zip"
STAGE="$ROOT/.build-stage.$$"
trap 'rm -rf "$STAGE"' EXIT INT TERM
rm -f "$ZIP"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$ROOT/module/." "$STAGE/"

# A Windows checkout may expose CRLF even though the Git object is normalized
# to LF. Android /system/bin/sh rejects CRLF scripts, so make the release ZIP
# deterministic and safe regardless of the host checkout policy. The Magisk
# module currently contains text files only.
find "$STAGE" -type f -exec sed -i 's/\r$//' {} +
(
  cd "$STAGE"
  zip -qr "$ZIP" . -x '*.DS_Store'
)
echo "$ZIP"

