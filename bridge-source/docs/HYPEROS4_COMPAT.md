# HyperOS 4 / Android 17 compatibility (E3N fork)

Base project: [Howard20181/HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live), GPL-3.0 licensed.
Compatibility reference: [upstream PR #30](https://github.com/Howard20181/HyperOS_FCM_Live/pull/30) by 793354162, targeting HyperOS 4 / PowerKeeper 4.2.00.

## Goals

- Preserve Android 17/HyperOS 4 support without silently dropping the entire FCM hook chain when one legacy method or member disappears.
- Integrate upstream PR #30 (`GmsObserver.updateFrameworkGmsNetStatus(boolean)`, optional legacy `NetdExecutor` and observer methods) into the mainline LSPosed API 102 HookBuilder implementation.
- Treat Greeze hooks individually, rather than failing the entire Greeze hook when `triggerGMSLimitAction`, UID lookup, `isAllowBroadcast`, or `deferBroadcastForMiui` is absent.
- Support `mSystemBlackList`/`SYSTEM_BLACK_LIST` and `mUseDataWhiteList`/`USE_DATA_WHITE_LIST` variants for `ListAppsManager`.
- Log *confirmed hooked methods* separately from *missing methods*. An absent method is a compatibility status, not proof that the remaining behavior is working.
- Preserve other original hooks; do not touch Magisk Millet Guard, battery, Wi-Fi or GMS installation.

## APK identity

The fork uses application ID `io.github.e3n.hyperos.fcmlive` to **coexist** with the author's signed package `io.github.howard20181.hyperos.fcmlive`. Do not enable both copies of the hook module simultaneously.

When you install the fork, open **LSPosed → Modules → HyperOS FCM Live · E3N OS4**, enable it and ensure System Framework (`system_server`) and PowerKeeper are in scope. Leave the original module **disabled**. Then reboot and examine new LSPosed module logs. Only positive "Hooked ..." messages show that an individual hook registered.

## Validation checklist

1. `lspd` and `system_server` remain stable; no new fatal crashes.
2. For `GmsObserver`, expect the new `updateFrameworkGmsNetStatus` hook on PowerKeeper 4.2.00; legacy method absence should be logged as INFO, not ERROR.
3. The Greeze broadcast and ListAppsManager hooks may be absent on some HyperOS 4 builds. Distinguish missing from successful. Do not claim full compatibility based solely on zero error logs.
4. Confirm `persist.sys.powmillet.enable`, `mGmsLimitEnabled`, device-idle GMS whitelist, and Google MCS TCP 5228/5229/5230 connectivity.
5. Only device-to-device messages tested over several hours of locked standby can verify actual FCM delivery latency.

## Risks

Modifying proprietary OEM system services is not guaranteed compatible with other ROM builds. A test passing CI only proves Java compilation, not correct runtime behavior. The fork is not a replacement for Xiaomi's or Google's device safety protections. Do not enable all hooks without a way to revert in LSPosed safe mode.

## License & attribution

GPL-3.0 inherited from the original project. PR #30 credited to 793354162; additional compatibility fallbacks by E3N.
