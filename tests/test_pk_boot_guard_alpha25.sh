#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
MODDIR=$TMP/module
mkdir -p "$MODDIR/backend" "$MODDIR/zygisk"
B=$MODDIR/backend
touch "$MODDIR/zygisk/arm64-v8a.so"
. "$ROOT/static-patch/overlay/bin/pk_boot_guard.sh"
A=11111111-1111-1111-1111-111111111111
C=22222222-2222-2222-2222-222222222222
D=33333333-3333-3333-3333-333333333333
E=44444444-4444-4444-4444-444444444444
F=55555555-5555-5555-5555-555555555555
G=66666666-6666-6666-6666-666666666666
ID=$A; FW='OEM/device/device:17/test/1:user/release-keys'; REASON=reboot,userrequested; COMPLETED=0
pk_boot_id() { printf '%s\n' "$ID"; }
pk_boot_firmware() { printf '%s\n' "$FW"; }
getprop() { case "$1" in sys.boot_completed) echo "$COMPLETED";; ro.boot.bootreason) echo "$REASON";; esac; }
reset_state() { rm -f "$B"/pk-boot.* "$B/powerkeeper-hook.disable"; ID=$A; COMPLETED=0; REASON=reboot,userrequested; FW='OEM/device/device:17/test/1:user/release-keys'; }
check() { if ! "$@"; then echo "FAIL: $*" >&2; exit 1; fi; }
absent() { [ ! -e "$1" ]; }
value() { [ "$(cat "$1")" = "$2" ]; }
printf 'pk.apk\tpresent\tmetadata\npk.gms.framework\tpresent\tmethod\n' > "$B/powerkeeper-capabilities.tsv"
pk_boot_pre; check value "$B/pk-boot.pending" "$A"
pk_boot_pre; check absent "$B/powerkeeper-hook.disable"
COMPLETED=1; pk_boot_ack; check absent "$B/pk-boot.pending"
pk_boot_pre; check absent "$B/pk-boot.pending"
printf '%s\n' "$A" > "$B/pk-boot.pending" # interrupted acknowledgement cleanup
ID=$C; COMPLETED=0; pk_boot_pre; check value "$B/pk-boot.pending" "$C"
check absent "$B/powerkeeper-hook.disable"
echo 'PASS normal boot acknowledgement and same-boot idempotency'
ID=$D; REASON=watchdog; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"
COMPLETED=1; pk_boot_mark_safe; check test -f "$B/pk-boot.safe"
ID=$E; REASON=watchdog; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"; check absent "$B/pk-boot.retry-used"
REASON=reboot,userrequested; pk_boot_pre; check absent "$B/powerkeeper-hook.disable"; check test -f "$B/pk-boot.retry-used"
pk_boot_pre; check absent "$B/powerkeeper-hook.disable"
ID=$F; REASON=watchdog; COMPLETED=0; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"
COMPLETED=1; pk_boot_mark_safe; ID=$G; REASON=reboot,userrequested; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"
echo 'PASS unknown failure, bounded recovery trial and repeat failure quarantine'
reset_state
printf '%s\n' "$A" > "$B/pk-boot.pending"
printf '%s\n' 'previous boot not acknowledged: native PowerKeeper hook quarantined' > "$B/pk-boot.status"
touch "$B/powerkeeper-hook.disable"
ID=$C; COMPLETED=1; pk_boot_mark_safe
ID=$D; COMPLETED=0; pk_boot_pre; check absent "$B/powerkeeper-hook.disable"
COMPLETED=1; pk_boot_ack; check absent "$B/pk-boot.retry-used"; check absent "$B/pk-boot.pending"; check absent "$B/pk-boot.auto-quarantine"
echo 'PASS legacy alpha24 migration via completed quarantined boot'
reset_state; touch "$B/powerkeeper-hook.disable"; COMPLETED=1; pk_boot_mark_safe
ID=$C; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"; check absent "$B/pk-boot.safe"
echo 'PASS manual disable is never cleared'
reset_state; pk_boot_pre; ID=$C; pk_boot_pre; COMPLETED=1; pk_boot_mark_safe
FW='OEM/other/other:16/test/2:user/release-keys'; ID=$D; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"
echo 'PASS changed firmware requires its own completed boot'
reset_state; ID=''; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"; check absent "$B/pk-boot.pending"
echo 'PASS missing boot identity fails closed'
reset_state; pk_boot_pre; ID=$C; pk_boot_pre; COMPLETED=1
printf 'pk.apk\tpresent\tmetadata\npk.equivalence\tunverified\tmetadata\n' > "$B/powerkeeper-capabilities.tsv"
pk_boot_mark_safe; check absent "$B/pk-boot.safe"; ID=$D; pk_boot_pre; check test -f "$B/powerkeeper-hook.disable"
echo 'PASS no applicable OEM method does not authorize native retry'
reset_state; rm -f "$MODDIR/zygisk/arm64-v8a.so"; pk_boot_pre; check absent "$B/pk-boot.pending"; check absent "$B/powerkeeper-hook.disable"
echo 'PASS no native payload leaves base guard independent'
echo 'ALL PK BOOT GUARD TESTS PASS'
