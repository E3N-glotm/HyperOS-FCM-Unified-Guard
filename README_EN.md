# HyperOS FCM Unified Guard

**[简体中文](README.md) | English**

A single Magisk module combining the Millet/FCM guard, adaptive framework policies, and a scoped **PowerKeeper Zygisk native runtime**. Current recommended release: **v0.4.0-alpha.9 (Latest)**. Neither the FCM Live APK nor LSPosed is required. PowerKeeper native hooks require ARM64 and working Zygisk/Zygisk Next; the base guard and framework backend run independently when Zygisk is unavailable.

**[Latest Release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) · [Download Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip) · [SHA-256](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip.sha256)**

> This is still a test build. GitHub's Latest label provides a current download entry; it does not mean that cross-device, real OTA, end-to-end push or battery validation is complete. See the [validation record](static-patch/VALIDATION.md).

## v0.4.0-alpha.22 (preview): Android 17 native DNS cache recovery fix

[Full alpha22 Magisk release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.22).

On November 12, 2026, two major FCM outages (00:18–04:32 and 05:32–07:12 local time) coincided with Android native DnsResolver failures for GMS UID 10139 **and several unrelated application UIDs**, even though explicit root upstream DNS queries worked. Restricted Box restarts and GCM_RECONNECT did not immediately restore DNS. Therefore the evidence does **not** isolate the underlying cause to GMS, Box or PowerKeeper alone.

The old DNS cache recovery attempts, using `ndc resolver flushnet` or `cmd netd resolver flushnet`, are unavailable on the tested Android 17 build, resulting in repeated ineffective recovery attempts. Alpha22 verifies SDK37, the official DNSResolver Binder service, a read-only isAlive reply and actual active NetId caches before invoking the AOSP Android 17 `IDnsResolver.flushNetworkCache(int netId)` API (Binder transaction 11). This operation succeeded in a real-phone test without disconnecting GMS.

Each confirmed outage and identical network-cache set receives **at most one successful Binder cache refresh**; a changed network set or a new outage may trigger another. Unverified Android releases never receive a guessed Binder transaction. This is independent of Box4Magisk and does not change routing, DNS servers, firewall rules, PowerKeeper, Zygisk, heartbeats or user proxy settings. The alpha21 neutral-unknown health indicators remain unchanged.

**Scope limitation:** This resolves a demonstrated broken cache-recovery API path, not yet a proven unique cause or cure for all overnight DNS outages. Subsequent overnight on-device data must verify whether real disconnects become shorter. Distributed as prerelease, not stable Latest.

## v0.4.0-alpha.21 (cross-ROM warning evidence refinement)

[Alpha21 release and full Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.21).

Extends alpha20's confirmed-defect-only warning policy to OEM whitelist results that vary among HyperOS versions. A nonempty response from `MILLET_NO_RESTRICT_APP` or `cmd deviceidle whitelist` is **not** proof that GMS is excluded: help text, permission errors, empty/null and unknown formats are neutral gray. Yellow is permitted only if a real Android package-name list or complete `system/user,package,UID` entries can be parsed and GMS is verifiably absent; a confirmed GMS entry remains green.

The current health script and legacy static-overlay health script were subjected to 15 actual POSIX-shell response scenarios, in addition to all existing alpha20 tests. The official alpha21 ZIP is built from the signed alpha20 baseline; only the health script, version metadata and release note differ, and every unrelated file is byte-identical. No change to FCM connectivity, Box recovery, Zygisk, PowerKeeper, wake alarms or device networking. Box4Magisk remains optional and its absence does not itself trigger yellow.

**Use alpha21 rather than interim alpha20 for cross-ROM distribution.** Still a preview; no claim of end-to-end push reliability or device-wide runtime verification.

## v0.4.0-alpha.20 (preview): Unknown or unverified is not a warning

[Alpha20 full Magisk ZIP and release notes](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.20).

Fixes a recurring false-positive yellow state across multiple HyperOS devices. Previous health scripts elevated *unverified* PowerKeeper ART method execution, missing DNS hook hits, stale FCM observations, pending framework reboot, initial kernel alarm wait and absent capability reports to `YELLOW`. The aggregate then marked the whole Magisk module as partially broken. A separate startup/backend status writer also marked all transitional phases yellow, overriding otherwise healthy status.

**Evidence-based semantics:** green means the checks that were actually verified are healthy (with the number of outstanding unverified items disclosed); gray/white means observation unavailable, not yet triggered, not yet verified, or pending next normal boot; yellow now requires an explicit observed functional defect (e.g. OEM GMS limiter still enabled, confirmed non-whitelisting, confirmed kernel wake failure, native runtime quarantined, explicit native hook failure or a framework feature reporting failed/error); red marks a confirmed severe outage or backend ERROR/QUARANTINED.

Both the running health script and boot-phase Magisk module-status publisher have been corrected, including the legacy static-overlay variant. CI executed the status precedence scenarios and all older regressions, building the full distribution from the official alpha19 ZIP while requiring every unrelated file to remain byte-identical. No new workers or network probes were added. FCM/Box recovery, Zygisk/PowerKeeper code, wake timers, and users' network configurations are unchanged. Box4Magisk is optional and its absence is not itself a warning.

Gray does **not** certify success; green does not certify delivery of every end-to-end push. Alpha20 remains a preview rather than stable Latest.

## v0.4.0-alpha.19 (preview): Fix silent Box PID EOF abort in the FCM DNS recovery path

[Alpha19 full Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.19).

The root cause of the **unreachable recovery code**, not necessarily of the underlying DNS outage, is now confirmed. During the November 10 incident, the alpha18 recorder showed `root_gms_dns_differential_present`: GMS UID libc DNS lookup failed, explicit Root upstream DNS resolved, mobile IPv4 routing worked, Box DNS capture was present, sing-box was running, and the recovery cooldown was ready. Despite this, no recovery state had ever been created.

An isolated on-device shell trace established that the actual Box4Magisk `/data/adb/box/run/box.pid` contained `13508` **without a trailing newline**. The original `read -r proxy_pid < "$BOXPID" || exit 0` returned nonzero on EOF, even when it had already populated the variable; therefore the helper exited before checking recovery gates. Alpha19 switches to `proxy_pid=$(cat "$BOXPID" 2>/dev/null) || exit 0`, retaining strict decimal PID, live process identity, sustained-outage, DNS differential, Box DNS capture, IPv4 route, and one-per-outage/six-hour cooldown checks.

An on-device isolated mock verified the original abort, successful corrected gating, exactly one fake Box service restart with a simulated current GMS DNS lookup error, and suppression on repeat calls. The actual sing-box and GMS processes were not restarted during the tests. CI passed the entire existing regression suite and checked that every unchanged ZIP entry matches the official alpha18 release byte-for-byte. No native Zygisk/PowerKeeper, wake alarm, guard polling, firewall, user proxy, or OEM settings are modified.

The published preview ZIP has been staged using Magisk on the phone, and its corrected helper has been hot-applied to the running installation while FCM remained connected. A future **actual** recovery may briefly interrupt other proxied applications; it is still gated to one per outage with a six-hour global floor. **This fixes the recovery branch's early exit, not a proven unique root cause of the overnight DNS failure; overnight reliability and end-to-end message delivery require further observation.** Alpha19 is a preview and is not designated stable Latest.

## v0.4.0-alpha.18 (preview): Bounded DNS failure flight recorder and low-power reconnect behavior

[Alpha18 release and complete Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.18).

**Observed:** On Nov 9, alpha17 still left FCM disconnected from 04:28:27 to 07:06:15, roughly **2h38m**, while Android's DNS resolver repeatedly failed to resolve `mtalk.google.com`. PowerKeeper ART hooks, dynamic GMS UID (10139), scoped TCP 5228–5230 bypass and base workers tested healthy. Alpha17's conditional Box recovery did not produce any recovery state, but the failed prerequisite remains unidentified. Box network monitoring reported temporary loss of a default IPv4 route at other times; there is no exact timestamp correlation to establish the entire overnight root cause.

**Alpha18** introduces read-only, staged DNS failure evidence **only after a real outage of at least 15 minutes with current GMS UID DNS still unresolved**. At most once every 15 minutes, it records Box availability and PID, process age, GMS UID, UDP/53 capture rule, IPv4 default egress, GMS libc DNS outcome, root's explicit upstream DNS result, and cooldown gates. The most recent result is written to `/data/adb/fcm_unified_guard/dns_differential/latest.tsv` and a bounded 96-line history to `history.tsv`. Distinct failure gates include `no_ipv4_route`, `upstream_or_transport_unavailable`, and `root_gms_dns_differential_present`. If both upstream and local network routing fail, this diagnostics layer does not restart GMS or Box.

During prolonged unresolvable DNS (beyond 15 minutes), repeated native GCM soft reconnect broadcasts are reduced from approximately every five minutes to at most every 30 minutes, while early recovery attempts and the existing DNS recovery logic are retained. No new resident process, wakeup, timer, DNS server, firewall rule, mobile-data toggle, proxy subscription change or OEM Hook is introduced. Original alpha17 Box recovery remains unchanged.

CI and on-device ZIP checks passed, including SHA-256 verification and byte-for-byte comparison of all unchanged native components against alpha17. The two scripts were safely hot-patched to the currently running alpha17 installation; FCM remained connected and sing-box retained the same PID. **Overnight message delivery and stability are still unverified**; this preview is not declared a permanent DNS outage fix.

SHA-256: `32afef60de85ce76f2a31e26f4a5aac1a9c2589b1837666ede059abe2736cf33`.

## v0.4.0-alpha.17 (preview): Differential DNS verification and tightly gated nighttime recovery

[Alpha17 release and complete Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.17).

On Nov 7 the phone running alpha16 again lost FCM connectivity from 05:08:31 to 07:27:33 (~2h19m) with repeated GMS UNKNOWN_HOST. Three PowerKeeper ART hooks were installed and key GMS exemptions were active; no independent OEM GMS DNS deny was recorded. Alpha16's only proxy recovery path required a particular sing-box stale-source-IP error message, absent from the overnight evidence. **The full root cause is still unproven; do not attribute every DNS outage exclusively to Box or PowerKeeper.**

Alpha17 retains alpha16's exact stale-source detection and adds an independent fallback after at least 15 minutes of a confirmed FCM outage, **only when GMS UID Android-libc DNS still fails with a recognized lookup error while explicit Root upstream DNS queries resolve mtalk.google.com**, Box's UDP/53 capture rule is present, IPv4 routing is available, sing-box has run for 20 minutes, and the user has not disabled or manually stopped Box. All these gates must pass before a single controlled recovery using Box's own service manager is allowed. There is **at most one fallback per outage**, a **six-hour minimum interval between fallback recoveries**, and differential probing no more than once per 15 minutes during a sustained outage. No additional background worker, alarm, global DNS settings, mobile data toggles or GMS process restarts are introduced.

Restarting Box can briefly interrupt other proxied application connections. This is an explicitly bounded tradeoff rather than a claim of proven root-cause repair. Existing Zygisk/PowerKeeper hooks, the native wake alarm, other guard components and user proxy/AdGuard Home settings are byte-for-byte unchanged. GitHub Actions passed regression and ZIP integrity checks. On-device online no-op tests left sing-box and GMS untouched, and isolated mock tests showed one controlled recovery with same-outage suppression and the six-hour floor. Both updated shell scripts were hot-patched into the running alpha16 module and the official alpha17 ZIP was saved to Downloads, but **overnight real-message delivery and battery-consumption equivalence remain unverified**.

SHA-256: `f527df3567ecc23597dcf18c6279c53e531ae607dc2f6e2933c5b1b5c9a0ec8e`.

## v0.4.0-alpha.16 (preview): Scoped repair of stale sing-box FCM DNS source addresses

[Alpha16 release and complete Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.16). On Nov 6, FCM disconnected between 04:14:31 and 06:42:02, reporting repeated GMS UNKNOWN_HOST. Three independent PowerKeeper hooks were demonstrably installed; no independent OEM GMS DNS deny was recorded. Therefore the missing-hook hypothesis does not explain the whole incident.

At 09:49:55, sing-box separately logged a concrete DNS socket failure: a lookup of `mtalk.google.com` attempted UDP from the no-longer-assigned cellular address `10.101.129.20` to `223.5.5.5:53` and failed with `network is unreachable`. The live cellular and Wi-Fi addresses were `10.22.168.76` and `192.168.220.101`. Box's anti-churn network handler preserved the living sing-box process through several default-route and IP transitions, which need not mean its previously-bound DNS socket remains usable. This later failure is proven; its exact contribution to the entire overnight outage is **not** proven.

Alpha16 invokes a narrowly gated diagnostic/repair **only on an already-observed GMS-UID DNS failure**. A Box restart through its own service manager is permitted only when a fresh (15-minute) sing-box log proves an `mtalk.google.com` UDP/53 `network is unreachable` failure from an IPv4 source no longer assigned to any active interface, belonging to the current sing-box PID/start time, with a usable route present. Duplicate error evidence cannot trigger again; recoveries are spaced by at least 30 minutes. A manually stopped/disabled Box is untouched. Normal FCM operation adds no polling, alarm or restart.

All original GMS and OEM hooks, the native Zygisk library, scoped wake alarm, FCM recovery policy, and user DNS/proxy configurations remain unchanged. Android isolated mocks verified the allow/deny conditions; CI passed policy regressions, ZIP integrity checks and byte-level comparisons against alpha15. The currently running phone already received a non-disruptive hotfix of the two shell files, while installing alpha16 is needed to make it an upgradeable Magisk release. Neither nighttime FCM reliability nor end-to-end push delivery is yet proven.

SHA-256: `04f5c4759b33b619b3556b6d7b3d5738c4b07a183b10b2dd86e8494c9d6a5559`.

## v0.4.0-alpha.15 (preview): Fix PowerKeeper runtime audit across Android mount namespaces

[Alpha15 release and complete Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.15). A real-device investigation on Nov 5 confirmed that the PowerKeeper app's Device-Encrypted private audit lives in its **own mount namespace**. The file exists under `/proc/<PowerKeeper_PID>/root/data/user_de/0/com.miui.powerkeeper/files/fcmu_pk_runtime_alpha14.tsv` although the Magisk shell's direct `/data/user_de/0/com.miui.powerkeeper/files/` path does not exist. Alpha14's apparent missing-hook report was therefore a **diagnostic false negative**.

The recovered audit proves that the GmsObserver, GMS-UID DNS and Doze PowerKeeper ART hooks were actually installed and invoked. The bootstrap OEM allow was called for the actual GMS UID (10139) at **12:04:50**. The FCM monitor reported Android DNS recovery at **12:05:03**, 13 seconds later. This is temporal evidence, not proof of sole causation or successful end-to-end message delivery.

Alpha15 fixes health reporting by using the current PowerKeeper PID's mount namespace, same-boot timestamp and exact attach PID; it also distinguishes the bootstrap allow from an **independent OEM GMS DNS deny request successfully redirected** by the hook. A new `PK_DNS_DENY` event is reported only for the latter. The native Zygisk library, kernel alarmtimer, core FCM recovery and existing user network settings remain unchanged.

The alpha14 health script was also safely hot-fixed in place and validated on the running phone; alpha15 requires Magisk installation and a normal reboot for its new Java event evidence. Neither overnight delivery parity nor the full legacy LSPosed system_server hook equivalence has been established. SHA-256: `b4700f9ba77d2cf9f6600f51d06bf29e590c06c359216970eb207e2bde515e17`.

## v0.4.0-alpha.14 (preview): Restore pre-existing GMS DNS permissions and attest real PowerKeeper hooks

[Download alpha14](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.14). The November 5 overnight session again reported roughly 2h36m of `UNKNOWN_HOST` / FCM disconnection. Although alpha13 included a Zygisk-based PowerKeeper hook, a mapped native library did not prove that any ART method was installed or called. A future-deny interceptor also cannot retroactively undo a GMS UID DNS deny set before the interceptor was installed.

Alpha14 adds a **single, narrowly scoped OEM allow operation** through `NetdExecutor.setGmsDnsBlockerState(actualGmsUid,false)`, but only after the installed PowerKeeper APK byte fingerprint/previously audited method semantics, runtime GMS UID, and actual `hook_installed` result all match. Unknown APKs, failed hooks, and other UIDs retain their original behavior. No system-wide DNS, Box4Magisk or AdGuard Home configuration changes.

For post-reboot verification, the PowerKeeper process writes a small, one-shot audit into its own Device-Encrypted app storage, recording Java attach, method installation results, initial DNS allow status and the first successful call of each method. Health output separately reports `PK_DNS_HOOK` and `PK_DNS_HIT`, rejecting stale files from earlier boots. This adds no service, polling loop or recurring wake alarm.

The ZIP was built/tested on CI and checksum-verified on the phone, but the user must install and reboot before runtime hook and overnight real-message delivery can be validated. The old E3N FCM Live system_server broadcast hooks are **not proven equivalent** to the current static framework patches. This remains a prerelease, not a stable Latest.

## v0.4.0-alpha.13 (preview): Restore E3N FCM Live GMS DNS protection

[Download alpha13 prerelease](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.13). On Nov 4, alpha12 observed a ~2h29m MCS outage during screen-off idle. The GMS Android resolver reported UNKNOWN_HOST until 07:10, and recovery succeeded at 07:12. The legacy Millet Guard + E3N FCM Live combination also intercepted PowerKeeper's GmsObserver and OEM GMS network restrictions—functionality not equivalent to a simple keepalive, whitelist or TCP port bypass.

Alpha13 adds a **GMS-UID-only DNS deny prevention hook** to the existing Magisk Zygisk/ART PowerKeeper bridge. It is enabled only when the actual PowerKeeper APK SHA-256 matches bytecode semantics independently verified on the test ROM, and the GMS UID can be obtained dynamically. For `NetdExecutor.setGmsDnsBlockerState(int uid, boolean deny)`, only a deny request for the real GMS UID is changed to allow before invoking the OEM method. All other UIDs and rules remain unchanged; unknown APKs fail closed, retaining the base module. This fingerprint is for APK semantics, not a handset model whitelist.

The full ZIP was rebuilt and validated in CI and on-device. The original native library, alarmtimer, other policies, user Box4Magisk/AdGuard Home configurations and alpha12 FCM core are preserved. **The new hook still requires installation/reboot and runtime hit verification; no claim of completed overnight push or battery parity is made.** This release is not Latest.

## v0.4.0-alpha.12 (preview): Overnight FCM stability fix

The Nov 3 device logs revealed two prolonged MCS outages (02:51–05:14 and 06:09–07:14). With alpha11, the guard injected an `MCS_HEARTBEAT` every ten minutes even while connected, and each injection frequently coincided with an endpoint change. It also probed mtalk TCP reachability as root, which can use a different Box4Magisk/TProxy route from the actual Google Play services UID. On the test device, a root TCP probe succeeded for an IP while the same probe under GMS's UID failed. Repeated process restarts did not establish MCS.

**alpha12** removes unsolicited heartbeats during healthy sessions, uses GMS-UID-bound Android DNS and TCP reachability checks before the process-level fallback, and applies increasing cooldowns after unsuccessful GMS restarts (global minimum 1 hour, then 3/6/12 hours). The previous soft `GCM_RECONNECT`, Android DNS recovery, kernel wake alarm, Zygisk/PowerKeeper and framework policies remain intact. It does not alter Box4Magisk or AdGuard Home user settings.

[Download alpha12 preview](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.12). Verified with 8 regression tests, real-device UID network comparisons, and release ZIP integrity checks. Overnight delivery reliability and standby power have not yet been validated.

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
