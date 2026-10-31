# HyperOS FCM Unified Guard

**[简体中文](README.md) | English**

A single Magisk module combining the Millet/FCM guard, adaptive framework policies, and a scoped **PowerKeeper Zygisk native runtime**. Current recommended release: **v0.4.0-alpha.9 (Latest)**. Neither the FCM Live APK nor LSPosed is required. PowerKeeper native hooks require ARM64 and working Zygisk/Zygisk Next; the base guard and framework backend run independently when Zygisk is unavailable.

**[Latest Release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) · [Download Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip) · [SHA-256](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip.sha256)**

> This is still a test build. GitHub's Latest label provides a current download entry; it does not mean that cross-device, real OTA, end-to-end push or battery validation is complete. See the [validation record](static-patch/VALIDATION.md).

## v0.4.0-alpha.9: Restore the legacy native FCM soft recovery behavior

Following real mobile-idle outages lasting approximately 48 and 93 minutes, source-level comparison with Millet Guard v2.1.x and E3N FCM Live revealed a behavioral regression: alpha.8 added Android DNS reachability as a prerequisite for the **non-disruptive native `GCM_RECONNECT` broadcast**. Alpha.9 restores the original distinction: after 10 minutes of sustained disconnection while the GMS reconnect alarm remains scheduled, one native soft attempt is permitted at most every 15 minutes, even when DNS is temporarily unavailable. Strict DNS/TCP validation remains mandatory for any last-resort GMS process restart.

The existing **single logcat event worker** also recognizes native `gtalk_connection` events, reusing its 15-second coalescing and 120-second fallback checks. No new daemon, wake lock, periodic wake alarm, global firewall exception or WeChat token reset is introduced. Both scripts were hot-deployed on the Android 17 device and its GMS/MCS connection and three workers were checked afterward. This **does not prove** overnight push delivery equivalence or that long outages caused by cellular/DNS failures or Doze scheduling have been eliminated. See [PR #19](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/19) and the [legacy comparison](docs/fcm-legacy-combination-night-audit-20261031.md).

## v0.4.0-alpha.8: Integrated module, on-device validation

On 2026-10-30 the module was installed on an ARM64 / Android 17 device and passed **two normal reboots**. All 10 adaptive framework features were actually mounted, Zygisk Next registered the module and the PowerKeeper process mapped its native library. GMS remained in the Millet/DeviceIdle exemptions, the Greeze limiter reported false, the FCM TCP/5228 connection was established, and no new native crashes were observed. A yellow Magisk status may mean the integrated PowerKeeper Java method hooks and true end-to-end message delivery are **not independently proven**, not that the framework failed to load.

This alpha.8 build is the previous on-device baseline; the **Latest recommended download is now alpha.9**, with the alpha designation retained. Cross-ROM coverage, controlled real-message delivery, and long-term battery A/B testing remain outstanding. See the [on-device test report](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/15#issuecomment-6524287155) and the [integrated candidate guide](powerkeeper-runtime/docs/integrated-magisk-candidate-v040a7.md).

## 2026-10-31: Cellular FCM heartbeat ACK timeout recovery

A device log captured an MCS heartbeat timeout at 02:49 followed by roughly 48 minutes of failed reconnect attempts. The unified guard's native `GCM_RECONNECT` at 03:37 restored the MCS connection. The prior soft-recovery gate incorrectly required successful raw TCP 5228–5230 probing even though GMS may use HTTPS/443 fallback; this prerequisite belongs to the much more disruptive full GMS process restart.

From `alpha.8`, a continuously disconnected GcmService with a stalled-but-scheduled reconnect alarm may receive a native soft reconnect **after 10 minutes if Android DNS works**, rate-limited to **one attempt per 15 minutes**. This reuses the existing maintenance worker: no added polling thread, wake lock, global GMS/443 firewall bypass, process kill, or WeChat token reset. It does not guarantee fixed-time recovery when the carrier connection, DNS, or device-idle scheduling is unavailable. See [fix PR #17](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/17).

## Features and compatibility

There is no hardcoded device, Android/HyperOS version or ROM hash allowlist. Detection uses the actual classes, fields, methods and ART capabilities. Missing interfaces do not prevent installation: unavailable features are reported individually while the remaining features can be adapted. The base guard runs independently of the static framework backend.

| Feature | Current behavior |
| --- | --- |
| Millet/Greeze exemptions | Maintains the managed package list while retaining system management for other apps |
| FCM recovery | DNS awareness, native heartbeats, reconnect scheduling and restricted-process recovery; sing-box is optional |
| Static framework policies | Ten individually detected, generated and verified capabilities covering broadcasts, autostart, temporary exemptions, GMS restrictions and process/network lists |
| SwipeUpClean | Clears the stopped flag for recognized events involving managed apps without actively relaunching them |
| DeviceIdle | Observe by default; optional enforce mode removes only entries owned by this module |
| PowerKeeper | ARM64 scoped Zygisk/Java ART runtime, discovers compatible OEM methods at runtime; missing methods degrade individually. The GMS UID-scoped DNS experiment remains disabled by default |
| Magisk status | Health indicators in the module name/description; Action shows individual reasons and immediately checks/retries adaptation |

Unrestricted installation does not imply identical functionality on every ROM. Systems without HyperOS/OEM interfaces may provide only partial functionality; consult the status report. Broadcast policy includes stopped-package flag handling, so unchanged Force Stop push semantics cannot be guaranteed.

## Installation and upgrades

1. Download `HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip` from Releases. GitHub's automatic Source code ZIP is not an installable module.
2. Back up `/data/adb/fcm_unified_guard/`. When migrating from Millet Guard, also preserve its package list and ownership records. Existing `packages.list` and `unified.conf` are retained during upgrades; legacy configuration is imported only when no current configuration exists.
3. Install the ZIP in Magisk. Disable the duplicate legacy Millet Guard core. If FCM Live/LSPosed bridge features are enabled, disable the overlapping features to avoid duplicate policy handling.
4. Put one managed package name per line in `/data/adb/fcm_unified_guard/packages.list`. After a fresh installation, reboot normally and wait for adaptation to finish and request a reboot, then reboot once more. An existing usable cache may avoid this generation step.
5. After the final reboot, the module first reports that the framework is mounted and boot acknowledgement is pending, with no further reboot needed. Wait for the loaded status rather than rebooting repeatedly. Action inspects the core, FCM connection, exemptions and individual capabilities without regenerating healthy or pending caches.

The module ID is `fcm_unified_guard`. Incompatibility, detection failures and generation failures do not automatically disable or uninstall the whole module or reboot the phone. A duplicate legacy core is reported as a conflict and duplicate writes are avoided; the user chooses which core to keep. Uninstalling the old module can revoke its ownership records, so retain migration backups.

## Health indicators

| Indicator | Meaning |
| --- | --- |
| 🟢 Healthy | Current checks pass for base workers, FCM connection, exemptions and adapted framework features |
| 🟡 Partial/pending | Some interfaces are missing, diagnostics are unknown, adaptation is running or a new cache awaits a normal reboot |
| 🔴 Attention | An observed disconnection, missing worker, generation/mount error, conflict or unconfirmed patch boot needs inspection |

Gray feature entries indicate missing or unreadable OEM interfaces. Refresh the Magisk module list for the latest result, or tap Action to check immediately and retry failed adaptation. Status is tied to the current boot: a previous reboot request is discarded. Current-boot checking and mounted/awaiting-acknowledgement states mean wait, not reboot again. Green indicates that current checks passed, not proven message delivery. Connection errors can also originate from the network or GMS.

## After a system upgrade

Boot performs a quick cache check. When framework inputs change, the new system and base guard start normally, then available features are detected and rebuilt automatically. A verified cache loads on the **next normal reboot**. Reinstalling the same ZIP is unnecessary, and the module never reboots the phone automatically.

The first boot after an OTA can temporarily run in base mode. Static framework code cannot reliably replace an already running system_server, so old system JARs are not forced over a changed system. Existing caches are retained. Failed generation never uninstalls the module; an unconfirmed prior boot quarantines only the corresponding cache while the base core continues. Disabling or uninstalling the module remains the user's choice.

Hashes are calculated dynamically on the device for cache identity, integrity and generation-race checks, not installation eligibility. Identical failing inputs are not repeatedly compiled within one boot. Changed inputs or Action can trigger another check. See the [adaptive backend details](static-patch/README.md).

## Battery cost and validation limits

Status checks reuse the five-minute maintenance cycle and FCM health cache. The indicators add no resident process, AlarmManager wakeup or dedicated wake lock. The core shares log subscriptions and maintenance timers and filters unrelated settings events. Framework generation after system changes incurs temporary CPU and I/O work; it does not compile continuously.

Validation includes 34 policy checks, strict bytecode contracts, per-feature degradation tests and 30 Linux installation/boot/status/OTA-rebuild scenarios. On an ARM64 / Android 17 device, alpha.7 was installed with Magisk and **survived two normal reboots**. All 10 framework capabilities were confirmed loaded by bind mounts and SHA-256; the PowerKeeper process mapped the Zygisk native library; the GMS limiter was disabled, TCP/5228 was connected and no new native tombstone occurred. A previous isolated experiment confirmed two OEM Java hooks firing, but that result is not by itself a method-level confirmation of the integrated ZIP.

End-to-end push, cross-device testing and controlled battery A/B measurements remain pending. No measured battery-saving percentage is claimed; CPU/RSS samples cannot directly measure whole-device battery drain. See [current validation](static-patch/VALIDATION.md) and [legacy architecture records](docs/VALIDATION.md).

## Build from source

Use Python, JDK 17 and a local Android SDK with Android 36 and Build Tools 36.0.0:

~~~sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test-adaptive-runtime.py
python static-patch/package.py
~~~

These commands build only the **static core component** (alpha.6), not the latest integrated ZIP. To build alpha.7, compile the diagnostics-OFF ARM64 native Zygisk library using `powerkeeper-runtime/build-native.sh`, compile the Java DEX using `powerkeeper-runtime/build.py`, then combine them with the static core using `powerkeeper-runtime/package_unified_candidate.py` (as implemented by the native CI workflow). The integrated module includes a Zygisk native library and DEX, but no LSPosed bridge, APK or prebuilt OEM JAR. Vendor framework caches are created on the device.

The repository retains the legacy bridge integration in `module/`, `bridge-source/` and the root `build.sh`. **Running root `bash build.sh` builds the old v0.2.0 package.** Consult [v0.2.0 documentation](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/blob/v0.2.0/README.md) for that version; do not mix its installation steps with the current module.

## Attribution and licenses

- The base guard derives from [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) and retains the root [MIT license](LICENSE).
- Static policies derive from [Howard20181 / HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live) and the [E3N compatibility fork](https://github.com/E3N-glotm/HyperOS_FCM_Live), under GPL-3.0-only. Corresponding upstream source and the [GPL license](bridge-source/LICENSE) remain in `bridge-source/`; the current implementation is in `static-patch/`.
- The root MIT license does not cover GPL components. Both licenses are included in the module ZIP. Original bridge provenance is documented in [PROVENANCE.txt](module/bridge/PROVENANCE.txt).

### v0.4.0-alpha.5 fixes

Fixes DNS canonical-alias parsing for mtalk; adds a bounded native soft reconnect for lengthy outages despite scheduled reconnect alarms; splits only modified OEM DEX classes on dexlib2 16-bit reference overflow, subject to DEX and ART validation. Absent ROM fields still degrade only the affected features.

### v0.4.0-alpha.5: cross-ROM PowerKeeper capability reporting

Magisk Action can now inspect installed PowerKeeper APKs and report per-method `present`, `variant`, `unknown`, or `missing` without device/model/build allowlists. Missing APK, unreadable DEX, or different signatures never disables the core FCM guard. On-demand scanning does not add a resident process. **These reports do not activate PowerKeeper hooks or establish full equivalence with the earlier LSPosed solution.**

### v0.4.0-alpha.5: FCM status cache race fix

Fixes the misleading 'FCM unknown' display if the five-minute Magisk health check races with the separate two-minute guard status update. Invalid or stale cached observations trigger one bounded direct GcmService query during the existing health cycle; fresh observations incur no additional query. The health UI no longer overwrites the guard-owned observation file. No new background process or PowerKeeper hook is added.

### v0.4.0-alpha.6: truthful Action diagnostics

Action now reads the active generation's `capabilities.tsv` instead of requiring the optional `last-capabilities.tsv` and mistaking an absent historical report for framework failure. Previous build logs are clearly labelled as historical, and PowerKeeper APK/class metadata no longer inflates the count of method signatures. PowerKeeper hooks remain inactive. No new background processes or polling are introduced.
