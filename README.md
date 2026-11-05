# HyperOS FCM Unified Guard

**简体中文 | [English](README_EN.md)**

单个 Magisk 模块，集成 Millet/FCM 基础守护、按系统接口生成的自适应框架策略，以及 **PowerKeeper 专项 Zygisk 原生 Hook**。当前推荐版本 **v0.4.0-alpha.9（Latest）**：不依赖 FCM Live APK 或 LSPosed；PowerKeeper 原生功能需要 ARM64 及可用的 Zygisk/Zygisk Next，缺失时基础守护与静态策略仍独立运行。

**[Latest Release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) · [下载 Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip) · [SHA-256](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.9/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip.sha256)**

> 当前仍为测试版。GitHub 的 Latest 标记用于提供最新下载入口，不代表已完成多机型、真实 OTA、端到端推送或续航验收。详见 [验证记录](static-patch/VALIDATION.md)。

## v0.4.0-alpha.14（预览版）：修复旧 DNS 禁用遗留状态，并提供 PowerKeeper Hook 真正命中的证据

**[下载 alpha14 完整 Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.14)**。手机 2026-11-05 凌晨 04:39:52–07:16:07 再次断连约 2 小时 36 分钟，GMS 不断报告 `UNKNOWN_HOST`。旧 E3N FCM Live 动态保护 GMS 网络相关 OEM 接口，而统一模块 alpha13 只具备 Zygisk 库加载证据，没有 ART Hook 安装与真实调用证明；并且即便 Hook 成功，也不能自动清除其安装**之前**写入的 GMS UID DNS `deny`。

alpha14 在 PowerKeeper **实际 APK 字节哈希、已审计的 `NetdExecutor.setGmsDnsBlockerState(int,boolean)` 语义、动态获取的真实 GMS UID 和专项 Hook 实际 `hook_installed`** 全部通过的情况下，额外进行一次 OEM 原生 `setGmsDnsBlockerState(GMS_UID,false)`，尝试清除已有禁止规则。该行为不作用于其他应用 UID、不会修改全局 DNS / Box4Magisk / AdGuard Home；未知 APK、Hook 失败或 UID 不可验证时跳过此操作，基础 FCM 守护正常保留。

PowerKeeper 自身首次启动时仅写一次少量私有 DE 文件 `/data/user_de/0/com.miui.powerkeeper/files/fcmu_pk_runtime_alpha14.tsv`，记录 `Application.attach`、每项 Hook 是否真实安装、GMS UID 初始 DNS 允许是否调用及相关方法首次命中。健康状态新增 `PK_DNS_HOOK` 和 `PK_DNS_HIT`，使用**本次开机**时间窗判定，避免把旧日志当成本次成功；不增加后台进程、常驻日志采集、网络轮询及额外周期唤醒。GMS 心跳、内核 alarmtimer、框架策略、PowerKeeper 原生库及所有现有用户配置均继承 alpha13。

CI Java 测试、完整发行包构建及手机端 SHA-256 校验已通过；发布包 SHA-256：`9055e399d28a4ea7a7a4225e26416a423973d230f248c82e8bf5f3f98dc0d674`。手机尚未安装并重启 alpha14，**不能宣称运行时 Hook 已成功，也不能宣称下一晚实际推送、耗电或旧双模块全功能等效已通过**。旧 E3N FCM Live 在 system_server 内的动态广播 Hook 与单模块静态“10/10”仍需分别验证，不应混为一谈。

## v0.4.0-alpha.13（预览版）：旧 FCM Live 的 PowerKeeper GMS DNS 保护

**[下载 alpha13 预览版](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.13)**。

11 月 4 日凌晨 04:43:58–07:12:39，alpha12 在锁屏状态下发生约 2 小时 29 分钟 MCS 断连。多次原生软重连均因 Google Play 服务的 Android DNS `UNKNOWN_HOST` 失败；DNS 恢复后经 90 秒稳定观察与一次 GMS 兜底重连成功。本次对照旧 **Millet Guard + E3N FCM Live** 发现，原 LSPosed 版除了广播延迟和白名单保护，还拦截 PowerKeeper 的 `GmsObserver.updateFrameworkGmsNetStatus(boolean)` 以及 GMS 网络限制逻辑，单靠重连和 `5228–5230` 直连规则不能证明行为等效。

alpha13 复用已有的 Zygisk + ART / Java 桥接，以 Android 17 上安装的 PowerKeeper 4.2.00 **实际 APK SHA-256** 为语义验证门槛，动态通过 PackageManager 取得 GMS UID。仅在 `NetdExecutor.setGmsDnsBlockerState(uid, deny)` 目标 UID 符合当前 GMS、且 OEM 请求禁止 DNS 时将 `deny=true` 改为 `false`，然后调用原方法；非 GMS UID、已允许动作与其他 OEM 接口保持原样。指纹不匹配、GMS UID 获取失败或者 Zygisk Hook 不可用时，不启用此 DNS 专项修复，基础守护保持可用。这是**已验证 APK 内容的保守兼容门控**，不是简单限定机型名称。

新 DEX 重新编译并通过 Java 策略单元测试、精准 UID 与指纹门控回归，发布包经 GitHub Actions 与手机端完整性校验。**Zygisk 原生库、内核 alarmtimer、既有 FCM 核心、设置维护、Box4Magisk/AdGuard Home 用户配置均保持不变**。当前手机已下载 alpha13，但仍运行 alpha12；安装并正常重启后才能核实动态 Hook 的实际安装与调用。真实锁屏消息投递、长时断连和功耗 A/B 仍待验证，因此暂不设为稳定 Latest。

## v0.4.0-alpha.12（预览版）：夜间 FCM 连接稳定性修复

2026-11-03 实测记录显示，alpha11 仍在凌晨 **02:51–05:14** 和 **06:09–07:14** 出现两次长时间断连。进一步排查发现，守护脚本在健康状态下每 10 分钟主动发送 `MCS_HEARTBEAT`，日志几乎每次都伴随 MCS 端点改变；此外，脚本使用 root 身份检查 5228 端口，而 Box4Magisk 对 GMS UID 和 root 使用不同的路由策略，实机已复现「root 连接成功、GMS UID 连接失败」的情况。夜间多次 GMS 进程级重启也没有恢复实际的 MCS 端点。

alpha12 改为**健康连接只被动检测，不再人工强制发送心跳**；仅在观察到断连后执行受限的原生 `GCM_RECONNECT`。进程级兜底之前改用**当前 GMS UID** 进行 DNS 与 5228–5230 端口探测，不满足条件则禁止不必要的 GMS 重启；连续进程重启失败加入 1 小时全局最低间隔、之后逐级提高至 3/6/12 小时。继续保留 alpha11 的 DNS 恢复判断、90 秒稳定观察、内核唤醒、PowerKeeper/Zygisk、静态后端与全部安装逻辑，**不修改 Box4Magisk 或 AdGuard Home 配置**。

**[alpha12 预览版下载](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.12)**。已在 Android 17 实机进行 UID 路径交叉验证和 8 组回归测试，并对发布 ZIP 与在机热修复脚本逐字节比较。发布包 SHA-256 为 `4848c5e5fc1852e824c5dd3106bcec48786d73008db200a979bebfb79038971d`。**当前设备已应用 alpha12 守护脚本热修复，但完整模块版本号仍需安装 alpha12 ZIP 才会更新；夜间实际推送和功耗仍需要继续验证。**

## v0.4.0-alpha.11（预览版）：DNS 恢复后及时补救 FCM 断连

2026-11-02 的锁屏实机记录显示，在 04:46 至 07:25 的断连中，统一守护有持续执行内核闹钟与软重连，但 GMS 多次产生 `UNKNOWN_HOST`。旧逻辑将最近的错误事件当成 DNS 持续故障，可能不检查当前 DNS 是否已恢复便直接退出。alpha11 改为每轮先检查当前 Android libc 解析；DNS 确认不通时不重启 GMS，恢复后使用至少相隔 90 秒的两次 DNS 成功观测，再满足 MCS TCP 可达与原有限频条件后才允许进程级兜底。保留非侵入式 GCM_RECONNECT，且不调整 Box4Magisk / AdGuard Home 的用户配置。

**[下载 alpha11 预览版](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.11)**。这是完整继承 alpha10 内核唤醒、PowerKeeper/Zygisk、静态框架和之前热修复的安装包，GitHub Actions 回归验证通过。当前手机已热部署 alpha11 FCM 修复，但版本标识只有安装完整 ZIP 后才会变为 alpha11。**DNS 上游持续不可达时，任何软重连都不能保证立刻修复；真实夜间投递及旧双模块等效性仍待进一步实测。**

## v0.4.0-alpha.10（预览版）：深度休眠主动唤醒

2026-11-01 新增基于 ARM64 Linux `CLOCK_BOOTTIME_ALARM` 的内核唤醒计时器，以解决普通 shell `sleep` 无法主动唤醒深度休眠 CPU 的问题。健康状态新增 `WAKEUP`，可辨识真实内核唤醒和不支持时的退化模式；保留 alpha9 PowerKeeper/Zygisk 集成、静态 10/10 框架与配置迁移。断连后的软恢复门槛为已观察断连 90–120 秒，仍有软重连限频和 DNS/TCP 守护的进程重启兜底，不要求安装 LSPosed。

**[alpha10 预览版下载](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/tag/v0.4.0-alpha.10)**。当前仍标记为 Pre-release，不替换 alpha9 Latest。内核定时器已在 Android 17 的 ARM64 实机试运行，尚未完成完整一夜的真实 FCM 投递与待机耗电 A/B 测试；周期性主动唤醒可能增加耗电，其他机型不支持时安全退化至普通轮询。详见 [唤醒机制与验证说明](docs/alpha10-suspend-wakeup.md)。

## v0.4.0-alpha.9：恢复旧 Millet Guard + FCM Live 的 FCM 软恢复行为

2026-10-31 在真实蜂窝待机期间出现约 48 分钟和约 93 分钟的 MCS 长时间断连。对照旧 Millet Guard 和 E3N FCM Live 源码后，确认之前的 alpha.8 对**原生软重连**错误增加了 DNS 成功的前置条件；旧组合仅在考虑重启 GMS 进程时才使用严格的 DNS/TCP 验证。现已恢复旧版区分：持续断连超过 10 分钟且 GMS 重连闹钟显示已安排但仍未恢复时，每 15 分钟最多触发一次原生 `GCM_RECONNECT`，即使 DNS 暂时不可用也不会先阻断该非侵入式广播。对 GMS 进程重启的严格检查不变。

合并后的事件监听器现在还会在**已有单条 logcat 流**中识别 `gtalk_connection`，沿用原有 15 秒去抖及两分钟后备维护周期，利用已有 GMS 系统事件检查连接，不增加后台进程、唤醒锁、单独闹钟或清除微信 Token。两项修复已在手机上独立热部署，三条守护进程和当前 FCM TCP 连接正常；**长时间深度休眠和运营商断网的真实送达能力尚未完成新一轮夜间对照**。详见 [PR #19](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/19) 和 [旧组合审计](docs/fcm-legacy-combination-night-audit-20261031.md)。

## v0.4.0-alpha.8：单一模块实机验收

2026-10-30 已在 ARM64 / Android 17 手机上通过 Magisk 安装并完成**两次正常重启**。10/10 自适应框架能力已实际挂载，Zygisk Next 已登记并在 PowerKeeper 进程映射原生库；GMS 在 Millet/DeviceIdle 名单、Greeze 限制为 false，FCM 5228 连通且未新增崩溃。Magisk 若显示黄色“部分功能/适配中”，通常表示 PowerKeeper **方法级 Hook 与端到端消息到达尚无集成版独立证明**，不等于框架未加载成功。

该版本为此前的 alpha.8 验证基线；当前推荐下载已更新至 alpha.9，仍保留 alpha 标签；其他机型、真实推送到达率及长期续航 A/B 仍需进一步验证，不承诺所有 OEM 功能完全等效。详见 [PR #15 实机验收记录](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/15#issuecomment-6524287155) 与 [安装说明](powerkeeper-runtime/docs/integrated-magisk-candidate-v040a7.md)。

## 2026-10-31 蜂窝 FCM 长时间断联修复

已根据真实日志修复 GMS 心跳 `ERR_HEARTBEAT_ACK_TIMEOUT` 后，软重连被 5228–5230 专用 TCP 探测过严限制的问题。实机于 02:49 断开约 48 分钟后，在 03:37 由统一守护 `GCM_RECONNECT` 成功恢复；新版本改为**持续断连 10 分钟 + Android DNS 解析正常**即可进行一次限频软重连（最多每 15 分钟一次），而不是要求专用端口先连接成功。继续复用原有 120 秒维护任务，不新增唤醒锁、常驻线程或全局 GMS HTTPS/443 放行，也不会因此清除微信 Token 或重启 GMS。

该措施主要缩短**网络可用但 GMS 内部重连调度滞后**时的恢复机会；运营商断网、DNS 不通和 Doze 长时间停止用户态任务调度时，仍不能保证固定时间内恢复。旧 `v0.4.0-alpha.7` 的实机安装与框架 10/10 记录仍有效；`alpha.8` 是在相同单模块结构上的 FCM 恢复热修复。参见 [修复 PR #17](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/pull/17)。

## 功能与兼容性

不写死机型、Android/HyperOS 版本或 ROM 哈希白名单。安装时按实际类、字段、方法及 ART 能力检测，缺少接口仍可安装；不能使用的功能逐项报告，其余功能继续适配。基础守护独立于静态框架后端。

| 功能 | 当前行为 |
| --- | --- |
| Millet/Greeze 免冻结 | 按应用名单维护，保留其他应用的系统管理 |
| FCM 连接恢复 | DNS 感知、主动心跳、重连调度与受限进程恢复，不要求必须运行 sing-box |
| 静态框架策略 | 广播、自启动、临时豁免、GMS 限制及进程/网络名单等十项能力，分别检测、生成和校验 |
| SwipeUpClean | 处理管理名单中的识别事件，清除 stopped 标志，不主动重新启动应用 |
| DeviceIdle | 默认 observe；可选 enforce，仅撤销本模块添加的条目 |
| PowerKeeper 原生专项 | ARM64 Zygisk 原生库与 Java DEX，按实际 OEM 方法逐项适配；没有兼容方法时仅该项降级；DNS UID 实验候选默认关闭 |
| Magisk 状态 | 名称和描述显示状态灯，点击“操作”查看逐项原因并立即检查、重试适配 |

不设机型限制不等于所有 ROM 都有相同接口。非 HyperOS 或缺少 OEM 接口的系统可能只运行部分功能；实际结果以状态报告为准。静态广播策略包含停止包标志处理，不能承诺完全保留原系统的 Force Stop 推送语义。

## 安装与升级

1. 下载 Latest Release 中的 `HyperOS-FCM-Unified-Guard-v0.4.0-alpha.9-integrated-candidate.zip`，不要把 GitHub 自动生成的 Source code ZIP 当作安装包。
2. 备份 `/data/adb/fcm_unified_guard/`；若从旧 Millet Guard 迁移，同时保留旧名单与所有权记录。升级保留已有 `packages.list` 和 `unified.conf`，仅在首次没有配置时导入旧名单。
3. 在 Magisk 中安装 ZIP。关闭旧 Millet Guard 的重复守护；若此前启用了 FCM Live/LSPosed 桥接，关闭对应功能，避免与静态策略重复处理。
4. 将需要管理的应用逐行写入 `/data/adb/fcm_unified_guard/packages.list`。首次安装后正常重启，等待“自动适配中”变为“待重启生效”，再正常重启一次；已有可用缓存时可能无需这一步等待。
5. 最后一次重启后会先显示“框架已挂载，正在确认启动，无需再次重启”，等待确认完成后显示“框架已加载”。此时不要连续重启；点击“操作”可查看基础核心、FCM、豁免和各项静态功能，正常或待确认的缓存不会因此重复生成。

模块 ID 为 `fcm_unified_guard`。不兼容、检测或生成失败不会自动禁用、卸载整个模块，也不会自动重启手机。与旧核心同时运行时会报告冲突并避免重复写入，由用户决定保留哪一个。旧模块卸载可能撤销其管理记录，迁移时应保留备份。

## 状态灯怎么看

| 状态 | 含义 |
| --- | --- |
| 🟢 正常 | 当前基础进程、FCM 连接、豁免与已适配框架功能检查通过 |
| 🟡 部分可用/待生效 | 部分接口缺失、诊断未知、适配中，或新缓存等待下次正常重启 |
| 🔴 需要查看 | 已观察到断联、工作进程缺失、生成/挂载错误、冲突或补丁启动未确认 |

灰色功能项表示相关 OEM 接口不存在或无法读取。刷新 Magisk 模块列表可查看最近状态；“操作”会立即重新检查，适配失败时重试。启动状态只对应本次开机，上一次的“待重启生效”不会沿用；“正在检查本次启动”或“框架已挂载，正在确认启动”都应等待，无需再次重启。绿灯只说明当前检查通过，不能代替真实消息到达测试；连接异常也可能来自网络或 GMS。

## 系统升级后

开机快速检查当前缓存；框架内容变化后，先让新系统和基础守护正常启动，再自动检测并重建可用功能。新缓存校验成功后，在**下一次正常重启**加载，无需重装相同 ZIP，也不会自动重启。

OTA 后首次启动可能暂处于基础模式。静态框架代码无法可靠地在已运行的 system_server 中替换，因此不会强行把旧系统 JAR 覆盖到新系统上。已有缓存会保留；生成失败不自动卸载模块，上一轮未确认启动只隔离对应缓存，基础核心继续工作。是否禁用或卸载由用户决定。

哈希由设备动态计算，仅用于缓存身份、完整性与生成竞争检查，不是安装白名单。相同输入的失败在一次开机内不反复编译；输入变化或点击“操作”后可再次检测。详细流程见 [自适应机制](static-patch/README.md)。

## 耗电与验证边界

状态检查复用五分钟维护周期及 FCM 健康缓存，没有为状态灯增加常驻进程、AlarmManager 唤醒或专用唤醒锁。核心合并了日志订阅和维护定时循环，并过滤无关设置事件。系统变化后的框架生成会有一次性 CPU 与 I/O 开销，正常运行不会持续编译。

已通过 34 项策略检查、严格字节码契约与按功能降级测试，以及 30 项 Linux 安装/启动/状态/OTA 重建流程测试。当前 ARM64 / Android 17 设备已实际安装 alpha.7 并**正常完成两次重启**，10/10 框架功能以 bind-mount 与 SHA256 确认已加载，PowerKeeper 原生库已映射、Greeze GMS 限制已关闭，FCM 5228 已连接，未新增原生 tombstone。此前隔离实验中两个 OEM Hook 已实际触发，但不能直接将其视作集成版的方法级验证。

端到端消息、跨机型和同条件电池 A/B 尚未完成，不能给出实测省电比例。CPU/RSS 采样也不能直接换算整机耗电。参见 [新版验证记录](static-patch/VALIDATION.md)；旧架构记录在 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 从源码构建

需要 Python、JDK 17 和包含 Android 36 平台及 Build Tools 36.0.0 的本地 Android SDK：

~~~sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test-adaptive-runtime.py
python static-patch/package.py
~~~

以上命令只生成**静态核心子组件**（alpha.6），不等于集成版安装包。当前 Latest 的集成构建还需要按 `powerkeeper-runtime/build-native.sh` 生成 **关闭实验诊断**的 ARM64 Zygisk 库、按 `powerkeeper-runtime/build.py` 生成 DEX，最后通过 `powerkeeper-runtime/package_unified_candidate.py` 与静态核心打包；GitHub Actions 的 PowerKeeper 原生 CI 执行该流程。集成包不含 APK、LSPosed 桥接或预制厂商 JAR，厂商框架缓存仅在手机端生成。

仓库保留了旧版集成桥接的 `module/`、`bridge-source/` 与根目录 `build.sh`；**根目录 `bash build.sh` 构建的是旧 v0.2.0 包**。旧版安装说明请查看 [v0.2.0 文档](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/blob/v0.2.0/README.md)，不要与新版步骤混用。

## 来源与许可

- 基础守护源于 [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard)，保留根目录 [MIT 许可](LICENSE)。
- 静态策略源于 [Howard20181 / HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live) 及 [E3N 兼容分支](https://github.com/E3N-glotm/HyperOS_FCM_Live)，采用 GPL-3.0-only；对应源码及 [GPL 许可](bridge-source/LICENSE) 保留在 `bridge-source/`，新版实现位于 `static-patch/`。
- 根目录 MIT 不覆盖 GPL 部分。安装包附带两份许可证；原桥接来源可查 [PROVENANCE.txt](module/bridge/PROVENANCE.txt)。

### v0.4.0-alpha.5 故障修复

修复 FCM DNS 规范别名误判、长期断联时有条件的原生软重连，以及部分 OEM DEX 重写发生 `Unsigned short value out of range: 65536` 的问题；静态适配生成的结果仍须经过 ART 校验并在下一次正常重启加载。缺失的 OEM 字段继续独立降级，不会被标记为已适配。更多说明见 [静态适配说明](static-patch/README.md)。

### v0.4.0-alpha.5：跨 ROM 能力探测

新增 PowerKeeper 接口逐项探测，点击 Magisk 模块「操作」即可查看当前 ROM 的 DEX 方法和签名。找不到 PowerKeeper、类名或签名不同均不会禁用原有 FCM 守护。**此版本是诊断与兼容性基础设施升级，尚未增加 PowerKeeper Hook；接口被发现不等于效果已经等效。**

### v0.4.0-alpha.5：修复 FCM 在线却显示未知

修复 2 分钟 FCM 状态采样与 5 分钟 Magisk 状态刷新不同时序下，可能出现 `FCM未知 / 部分功能适配中` 的误报。状态缓存缺失或超过 5 分钟时，在原健康检查周期中追加一次限时检测；有效缓存不增加 GMS 查询。健康页不再改写 FCM 守护进程的观察文件，避免覆盖同时到达的更新。此修复仅改变诊断同步，不更改已有的 10 项静态策略、不添加后台工作进程，也不代表 PowerKeeper 已与原双模块完全等效。

### v0.4.0-alpha.6：修复“框架已加载但报告缺失”误报

修复 Magisk「操作」页面错误读取仅在异常场景生成的 `backend/last-capabilities.tsv`，导致已成功挂载 `10/10` 的框架被提示 `capabilities.tsv unavailable; generation may have failed`。现在优先读取当前代际的 `backend/<generation>/capabilities.tsv`，把上次构建日志明确标记为历史记录；PowerKeeper 的 APK/类存在不再计入可调用方法签名数，显示 `0 runtime hooks` 以防误解。先执行 APK 探测，再生成同一次健康报告。**只修诊断，无新增 Hook、轮询、框架改写，不影响基础 FCM。**
