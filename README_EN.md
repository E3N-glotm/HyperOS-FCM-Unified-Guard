# HyperOS FCM Unified Guard

**[简体中文](README.md) | English**

A single Magisk module with an independent Millet/FCM guard and static framework policies generated on the device from available system interfaces. Current version: **v0.4.0-alpha.3**. No FCM Live APK, LSPosed or Zygisk is required.

**[Latest Release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) · [Download Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.3/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.3-static.zip) · [SHA-256](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.3/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.3-static.zip.sha256)**

> This is still a test build. GitHub's Latest label provides a current download entry; it does not mean that cross-device, real OTA, end-to-end push or battery validation is complete. See the [validation record](static-patch/VALIDATION.md).

## Features and compatibility

There is no hardcoded device, Android/HyperOS version or ROM hash allowlist. Detection uses the actual classes, fields, methods and ART capabilities. Missing interfaces do not prevent installation: unavailable features are reported individually while the remaining features can be adapted. The base guard runs independently of the static framework backend.

| Feature | Current behavior |
| --- | --- |
| Millet/Greeze exemptions | Maintains the managed package list while retaining system management for other apps |
| FCM recovery | DNS awareness, native heartbeats, reconnect scheduling and restricted-process recovery; sing-box is optional |
| Static framework policies | Ten individually detected, generated and verified capabilities covering broadcasts, autostart, temporary exemptions, GMS restrictions and process/network lists |
| SwipeUpClean | Clears the stopped flag for recognized events involving managed apps without actively relaunching them |
| DeviceIdle | Observe by default; optional enforce mode removes only entries owned by this module |
| Magisk status | Health indicators in the module name/description; Action shows individual reasons and immediately checks/retries adaptation |

Unrestricted installation does not imply identical functionality on every ROM. Systems without HyperOS/OEM interfaces may provide only partial functionality; consult the status report. Broadcast policy includes stopped-package flag handling, so unchanged Force Stop push semantics cannot be guaranteed.

## Installation and upgrades

1. Download `HyperOS-FCM-Unified-Guard-v0.4.0-alpha.3-static.zip` from Releases. GitHub's automatic Source code ZIP is not an installable module.
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

Validation includes 34 policy checks, strict bytecode contracts, per-feature degradation tests and 30 Linux installation/boot/status/OTA-rebuild scenarios. An isolated installation and generation against the current phone's stock framework produced 10/10 capabilities with individual ART checks passing. **This does not establish successful cold activation of this build or a real OTA.**

End-to-end push, cross-device testing and controlled battery A/B measurements remain pending. No measured battery-saving percentage is claimed; CPU/RSS samples cannot directly measure whole-device battery drain. See [current validation](static-patch/VALIDATION.md) and [legacy architecture records](docs/VALIDATION.md).

## Build from source

Use Python, JDK 17 and a local Android SDK with Android 36 and Build Tools 36.0.0:

~~~sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test-adaptive-runtime.py
python static-patch/package.py
~~~

The ZIP and checksum are written to `dist/`. The package contains no APK, LSPosed/Zygisk bridge or prebuilt vendor JAR. Vendor framework caches are generated only on the device. Current-build CI covers `main` and the development branch.

The repository retains the legacy bridge integration in `module/`, `bridge-source/` and the root `build.sh`. **Running root `bash build.sh` builds the old v0.2.0 package.** Consult [v0.2.0 documentation](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/blob/v0.2.0/README.md) for that version; do not mix its installation steps with the current module.

## Attribution and licenses

- The base guard derives from [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) and retains the root [MIT license](LICENSE).
- Static policies derive from [Howard20181 / HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live) and the [E3N compatibility fork](https://github.com/E3N-glotm/HyperOS_FCM_Live), under GPL-3.0-only. Corresponding upstream source and the [GPL license](bridge-source/LICENSE) remain in `bridge-source/`; the current implementation is in `static-patch/`.
- The root MIT license does not cover GPL components. Both licenses are included in the module ZIP. Original bridge provenance is documented in [PROVENANCE.txt](module/bridge/PROVENANCE.txt).

### v0.4.0-alpha.3 fixes

Fixes DNS canonical-alias parsing for mtalk; adds a bounded native soft reconnect for lengthy outages despite scheduled reconnect alarms; splits only modified OEM DEX classes on dexlib2 16-bit reference overflow, subject to DEX and ART validation. Absent ROM fields still degrade only the affected features.
