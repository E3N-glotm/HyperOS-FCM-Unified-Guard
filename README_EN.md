# HyperOS FCM Unified Guard

This branch also provides the [Magisk-only v0.3.0-alpha.3 candidate](static-patch/README.md). It detects framework capabilities instead of checking a model/OS-build allowlist and generates a local policy without a separate APK or LSPosed. Cross-ROM runtime validation remains pending. The text below describes the published v0.2.0 architecture.

v0.2.0 integrates the Millet Guard core and the verified E3N FCM Live bridge in one repository and Magisk ZIP. **Full functionality requires LSPosed** with `system` and `com.miui.powerkeeper` scopes. The existing verified bridge is reused, not loaded twice.

The core streams filesystem events instead of spawning handlers for unrelated settings writes, separates FCM health from settings reconciliation, combines logcat subscriptions and maintenance timers, and eliminates redundant healthy-state GcmService dumps. Heartbeat-discovered disconnections still enter recovery. No additional wake lock or wakeup alarm is introduced.

Disable the original Millet Guard core before enabling this core. Preserve its package list and ownership records during migration. To install a missing bridge, run `sh /data/adb/modules/fcm_unified_guard/bin/bridgectl install`, enable its LSPosed scopes, and reboot. Existing APKs and scope databases are never overwritten. Uninstalling the core does not uninstall a pre-existing bridge.

This retains the original bridge's stopped-package broadcast flag behavior as well. Do not claim that all Force Stop semantics are unaffected. Hook registration and connection status are not proof of end-to-end delivery or longer battery life; see [validation](docs/VALIDATION.md).

Build: `bash build.sh`. Shell code is MIT under root `LICENSE`; the separately bundled bridge is GPL-3.0 and is NOT covered by that MIT license. Complete corresponding source and build scripts are in `bridge-source/`, including its GPL license. See `module/bridge/PROVENANCE.txt` for the exact revision and checksum. The bridge uses the original tested debug signature; rebuilding can produce a different certificate. Build its source with JDK 21, Android SDK 37 and `bash gradlew :HyperFCMLive:assembleDebug` from `bridge-source/`.
