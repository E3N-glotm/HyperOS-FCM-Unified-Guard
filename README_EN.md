# HyperOS FCM Unified Guard

**[简体中文](README.md) | English**

Experimental independent **Magisk-only** fork of the [Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) policy/FCM recovery engine. Adds native Android DeviceIdle exemption introspection and an explicitly opt-in GMS exemption. It does **not** use LSPosed, Zygisk Java injection, or hidden method patching.

**v0.1.1 is not a complete replacement for [HyperOS FCM Live](https://github.com/E3N-glotm/HyperOS_FCM_Live).** Its in-process PowerKeeper, Greeze and BroadcastQueue hooks cannot be replicated by ordinary shell commands. No GPL-3.0 Xposed source was copied into this MIT-licensed project.

The module retains the original owner's safe no-restrict reconciliation, GMS limiter probing, Android DNS-aware FCM recovery, stale MCS heartbeat checks, soft reconnect and narrowly scoped SwipeUpClean `stopped` repair.

## Installation

Install the Magisk ZIP and reboot, but do not run this alongside the original Millet Guard. The module will refuse to start its workers if the original Magisk module is enabled. It does not automatically disable any old module or LSPosed scope.

Runtime configuration:
- `/data/adb/fcm_unified_guard/packages.list` (defaults to GMS alone)
- `/data/adb/fcm_unified_guard/unified.conf`

`DEVICEIDLE_GMS_POLICY=observe` (default) is read-only. `enforce` requests native GMS exemption when it is not already present and remembers ownership for uninstall. Magisk Action displays the native audit and logs.

To compare with E3N FCM Live, explicitly disable its LSPosed scope separately, reboot, and test notification delivery, MCS uptime and battery usage on the same device/network. No lower battery usage or equal end-to-end FCM performance is claimed without an A/B trial. Restore your original module configuration if anything fails.

## Attribution and license

Derived from E3N [Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) under MIT. [HyperOS FCM Live](https://github.com/Howard20181/HyperOS_FCM_Live) by Howard20181 is GPL-3.0; its source and binaries are not included here.
