#!/system/bin/sh
# Only the optional PowerKeeper runtime is gated; the core is independent.
# A successful boot while quarantined is NOT proof that native injection works.
pk_boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
pk_boot_firmware() { getprop ro.build.fingerprint 2>/dev/null; }
pk_boot_valid_id() {
  case "$1" in ''|*[!0-9a-fA-F-]*) return 1;; esac
  printf '%s\n' "$1" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}
pk_boot_valid_firmware() {
  case "$1" in ''|*[!A-Za-z0-9_./:+-]*) return 1;; esac
}
pk_boot_write() {
  printf '%s\n' "$2" > "$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"
}
pk_boot_auto_quarantine() {
  [ -f "$pk_dir/pk-boot.auto-quarantine" ] ||
    [ "$(cat "$pk_dir/pk-boot.status" 2>/dev/null)" = 'previous boot not acknowledged: native PowerKeeper hook quarantined' ]
}
pk_boot_capable() {
  # Only concrete method evidence, not an APK/class or metadata marker.
  awk -F '\t' '$1 ~ /^pk\./ && $1!="pk.apk" && $1!="pk.gms.observer" && $1!="pk.gms.binder_chain" && $1!="pk.equivalence" && $2=="present" {ok=1} END {exit !ok}' "$pk_dir/powerkeeper-capabilities.tsv" 2>/dev/null
}
pk_boot_quarantine() {
  # Persist ownership before the native gate. Never replace a manual gate.
  [ ! -f "$pk_dir/powerkeeper-hook.disable" ] || return 0
  pk_boot_write "$pk_dir/pk-boot.auto-quarantine" auto || return 1
  touch "$pk_dir/powerkeeper-hook.disable" || return 1
  pk_boot_write "$pk_dir/pk-boot.status" "$1"
}
pk_boot_mark_safe() {
  pk_dir=$MODDIR/backend
  [ -f "$MODDIR/zygisk/arm64-v8a.so" ] || return 0
  [ "$(getprop sys.boot_completed)" = 1 ] || return 0
  [ -f "$pk_dir/powerkeeper-hook.disable" ] && pk_boot_auto_quarantine || return 0
  [ ! -f "$pk_dir/pk-boot.retry-used" ] && pk_boot_capable || return 0
  pk_id=$(pk_boot_id); pk_fw=$(pk_boot_firmware)
  pk_boot_valid_id "$pk_id" && pk_boot_valid_firmware "$pk_fw" || return 0
  pk_boot_write "$pk_dir/pk-boot.safe" "$pk_id $pk_fw"
}
pk_boot_pre() {
  pk_dir=$MODDIR/backend
  [ -f "$MODDIR/zygisk/arm64-v8a.so" ] || return 0
  pk_id=$(pk_boot_id); pk_fw=$(pk_boot_firmware)
  if ! pk_boot_valid_id "$pk_id"; then
    pk_boot_quarantine 'boot identity unavailable: native PowerKeeper runtime gated' || true
    return 0
  fi
  pk_old=$(cat "$pk_dir/pk-boot.pending" 2>/dev/null || true)
  if [ -f "$pk_dir/powerkeeper-hook.disable" ]; then
    # Legacy alpha24 auto-quarantine is recognized by its exact status.
    # A manual/unknown disable must NEVER be automatically removed.
    pk_boot_auto_quarantine || return 0
    [ ! -f "$pk_dir/pk-boot.retry-used" ] || return 0
    # Require a distinct completed boot under the same firmware, a concrete
    # compatible method, and explicit normal reboot evidence. Unknown boot
    # reasons cannot authorize an automatic trial (including on old ROMs).
    [ -r "$pk_dir/pk-boot.safe" ] || return 0
    read -r pk_safe_id pk_safe_fw < "$pk_dir/pk-boot.safe" || return 0
    pk_boot_valid_id "$pk_safe_id" && [ "$pk_safe_id" != "$pk_id" ] || return 0
    pk_boot_valid_firmware "$pk_fw" && [ "$pk_safe_fw" = "$pk_fw" ] && pk_boot_capable || return 0
    case "$(getprop ro.boot.bootreason 2>/dev/null)" in
      reboot,userrequested|reboot,adb|reboot,ota|reboot,update) ;;
      *) return 0;;
    esac
    # Consume the one trial BEFORE removing the gate. Failure is fail-closed.
    pk_boot_write "$pk_dir/pk-boot.retry-used" "$pk_id $pk_fw" || return 0
    pk_boot_write "$pk_dir/pk-boot.pending" "$pk_id" || return 0
    pk_boot_write "$pk_dir/pk-boot.auto-quarantine" auto || return 0
    pk_boot_write "$pk_dir/pk-boot.status" 'native PowerKeeper recovery trial: boot acknowledgement pending' || return 0
    rm -f "$pk_dir/powerkeeper-hook.disable"
    return 0
  fi
  pk_ack_id=$(cat "$pk_dir/pk-boot.acknowledged" 2>/dev/null || true)
  if pk_boot_valid_id "$pk_ack_id"; then
    # Acknowledgement is durable before pending cleanup, including power loss.
    if [ "$pk_ack_id" = "$pk_old" ]; then
      rm -f "$pk_dir/pk-boot.pending" "$pk_dir/pk-boot.safe" "$pk_dir/pk-boot.retry-used" "$pk_dir/pk-boot.auto-quarantine"
    fi
    [ "$pk_ack_id" != "$pk_id" ] || return 0
  fi
  if [ -f "$pk_dir/pk-boot.pending" ]; then
    # post-fs-data can be invoked twice in one boot; this is not a failure.
    [ "$pk_old" != "$pk_id" ] || return 0
    pk_boot_quarantine 'previous boot not acknowledged: native PowerKeeper hook quarantined' || true
    return 0
  fi
  # A failed write cannot silently allow an untracked boot.
  pk_boot_write "$pk_dir/pk-boot.pending" "$pk_id" ||
    pk_boot_quarantine 'cannot persist boot acknowledgement: native PowerKeeper runtime gated'
  return 0
}
pk_boot_ack() {
  pk_dir=$MODDIR/backend
  [ -f "$MODDIR/zygisk/arm64-v8a.so" ] || return 0
  [ "$(getprop sys.boot_completed)" = 1 ] || return 0
  [ ! -f "$pk_dir/powerkeeper-hook.disable" ] || return 0
  pk_id=$(pk_boot_id)
  pk_boot_valid_id "$pk_id" || return 0
  [ "$(cat "$pk_dir/pk-boot.pending" 2>/dev/null)" = "$pk_id" ] || return 0
  pk_boot_write "$pk_dir/pk-boot.acknowledged" "$pk_id" || return 0
  pk_boot_write "$pk_dir/pk-boot.status" 'boot completed; PowerKeeper Zygisk startup acknowledged; hook verification is separate' || return 0
  rm -f "$pk_dir/pk-boot.pending" "$pk_dir/pk-boot.safe" "$pk_dir/pk-boot.retry-used" "$pk_dir/pk-boot.auto-quarantine"
}
