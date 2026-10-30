# HyperOS FCM Unified Guard v0.4.0-alpha.6（静态核心组件说明）

> **说明（2026-10-30）**：本目录记录 **v0.4.0-alpha.6 静态核心子组件**，不包含 Zygisk。GitHub 当前 [Latest v0.4.0-alpha.7](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) 是在静态核心基础上再集成 PowerKeeper ARM64 Zygisk 原生专项的**单一 Magisk 模块**。下文“无 Zygisk / 尚未发布 Hook”的描述只针对本静态子组件，不能代表最新集成版本。新版安装说明请阅读仓库根目录 [README](../README.md)。

单个 Magisk 模块，保留 Millet/FCM 基础守护，并按当前框架可用能力生成静态策略；无需 FCM Live APK、LSPosed 或 Zygisk。

## 安装与兼容行为

不设置机型、Android/HyperOS 版本或预置 ROM 哈希白名单。只要 Magisk 能写入模块和配置目录，缺少 ART、OEM JAR 或个别方法不会阻止安装。可用的功能继续工作，缺失功能明确列入状态报告，不把“已安装”当成完整功能已经生效。

基础守护与框架后端独立启动。缺少静态策略、检测失败、生成失败或上一轮补丁启动未确认时，模块仍保留安装和启用状态；脚本不创建 disable/remove，不自动卸载或重启。与旧 Millet Guard 同时启用时，基础核心仍会拒绝重复写入，状态标红并说明冲突，由用户决定关闭哪一个。

## Magisk 状态灯

模块名称和描述显示状态；刷新 Magisk 模块列表可查看最近结果。点击“操作”会立即检查，适配失败时重试，并展开逐项原因与最近生成日志；正常、已挂载待确认或已有新缓存待加载时不强制重复生成。

| 指示 | 含义 |
| --- | --- |
| 🟢 | 当前基础工作进程、FCM 连接、豁免与已适配框架功能检查正常 |
| 🟡 | 部分接口未适配、诊断未知、正在生成或新补丁等待下次正常重启 |
| 🔴 | 已观察到连接断开、工作进程缺失、生成/挂载错误或补丁启动未确认 |

报告包含 CORE、FCM、Millet、GMS 限制、DeviceIdle，以及广播、自启动、进程/网络名单等十项静态功能。灰色项表示相关 OEM 接口不存在或无法读取。绿灯只表示当前检查通过，不能证明真实消息零延迟或百分百到达；连接红灯也可能由网络或 GMS 本身引起。

首次安装的通常流程是：安装 ZIP → 正常重启 → 等“自动适配中”变为“待重启生效” → 再正常重启一次。已有可用缓存时可直接加载。最后一次重启后，开机脚本立即更新为“正在检查本次启动”，挂载成功后显示“框架已挂载，正在确认启动，无需再次重启”，确认完成再显示“框架已加载”。无需为了检查状态而点击操作，更不要在启动确认期间连续重启。

状态记录绑定本次 boot ID，忽略上次开机或旧格式遗留的状态；挂载阶段只发布轻量的启动状态，不查询系统服务、不提前报全绿。完整健康检查还会确认框架文件，避免仅凭 ACTIVE 状态文件误报加载成功。

状态检查复用原来的五分钟维护周期，FCM 状态复用健康检查缓存；点击操作时立即重新读取。不增加常驻守护进程、AlarmManager 唤醒或专用唤醒锁。

## 系统升级自动适配

1. 开机快速检查缓存是否对应当前框架内容，无需机型/版本名单。
2. 当前缓存可用则在 system_server 启动前加载；源文件变化或缓存不可用时，先让新系统正常启动，基础守护持续运行。
3. Android 启动后自动检测并生成可用功能，对缺失接口或 ART 检查失败的功能逐项降级，其余功能继续生成。
4. 新缓存验证成功后显示“待下次正常重启生效”，下次正常重启自动加载；不需要重新刷 ZIP，也不自动重启手机。

静态 Java 框架代码无法可靠地在已运行的 system_server 中替换，因此 OTA 后的首次启动可能处于黄灯基础模式，框架扩展在后续正常重启加载。不会为了维持“已挂载”而用旧系统 JAR 覆盖新系统。这是当前静态路线的加载时机限制，不能宣传 OTA 首次启动即可完成全部扩展。

哈希均由本机动态计算，仅用于识别缓存、检查文件损坏与生成竞争，不作为安装准入白名单。重建采用新目录和原子指针切换，失败保留上一份缓存；上一轮未确认启动只隔离对应缓存，基础核心继续工作。点击操作可以主动重试，是否保留或卸载整个模块由用户决定。

自动生成不在 Magisk 的限时 post-fs-data 阶段运行；相同输入的失败在一次开机内不反复编译，确认无适配功能的输入会缓存结果，输入变化或用户点击操作后再检测。

## 功能与配置

基础核心保留按应用免冻结维护、GMS 限制处理、DNS 感知、主动心跳、重连调度恢复、受限进程恢复及 SwipeUpClean 处理。Box 端口例外仍按实际链是否存在处理；FCM 恢复不再要求必须运行 sing-box。

静态功能分为十项，单独检测所需类、字段和方法，并逐项 ART 校验：AMS 广播短时豁免/停止包标志、Greeze 广播放行/延迟/GMS 限制、Domestic 延迟、自启动、黑/白名单、网络与进程名单。不同 ROM 内部语义仍可能不同，部分适配不等于已经证明完全等效。

配置在 /data/adb/fcm_unified_guard，升级保留用户 packages.list 和 unified.conf；只在首次没有配置时导入旧模块名单。旧静态候选版的已验证缓存可尽量迁移，不要求先卸载。不要同时运行两个白名单维护核心。

## 构建与验证

~~~sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test-adaptive-runtime.py
python static-patch/package.py
~~~

安装包不含 APK、LSPosed/Zygisk 桥接或预制厂商 JAR。动态生成的文件仅在用户设备本地保留。编译只使用本地 SDK/JDK，不使用系统代理。

已通过 34 项策略检查、严格契约与按功能降级测试，以及 30 项 Linux 安装/启动/状态/OTA 重建等流程测试。当前手机的原厂框架在独立 ART 进程中生成十项功能并逐项验证成功，生成结果与已验证的完整策略哈希一致。离线测试不改动活动挂载；真实 OTA 后的完整冷启动、端到端消息和电池 A/B 尚未验收，详见 VALIDATION.md。

## 许可

静态策略源于 Howard20181 的 HyperOS_FCM_Live 与 E3N 修复分支，GPL-3.0-only；已有守护核心保留 MIT。完整 GPL 许可和上游对应源码在 ../bridge-source，安装包附带两份许可证。不能用根目录 MIT 许可覆盖 GPL 部分。

## v0.4.0-alpha.3 修复说明

- 修复 Android 解析别名后 `ping` 显示 `mobile-gtalk.l.google.com` 时，守护程序错误认定 `mtalk.google.com` DNS 失败并长时间禁止恢复。
- 长时间断联、重连闹钟仍显示已安排且端口可达时，每 30 分钟最多发送一次原生 GCM_RECONNECT，优先于终止 GMS 进程。
- 静态 OEM DEX 超过 16 位索引上限时仅对该种写入失败执行分离重建，保留原文件未修改的类，单独生成修改类 DEX；仍经 DEX/ART 检查后才能启用。
- 部分 ART 对 `-Xmx1024m` 启动异常，适配器改为 `-Xmx512m`。跨 ROM 效果仍取决于实际类、字段、ART 校验和冷启动结果。
- 系统诊断中的 Greeze 和 Millet 状态分开检测，框架报告缺失显示未知而不是 `0/0`。

## PowerKeeper 多机型兼容探测（源码新增，未发布）

Magisk 操作页新增只读的 PowerKeeper DEX 探测器。它根据 `pm path` 和安装包列表发现当前设备的 APK，解析全部 `classes*.dex`，按方法签名检查 GmsObserver、NetdExecutor、Doze 相关功能，而不是依据机型代号、HyperOS 版本或 ROM 哈希做白名单。每项报告 `present` / `variant` / `missing` / `unknown`；无法访问 APK、没有 PowerKeeper、DEX 读取失败都不会禁用基础 FCM 守护。

注意：此功能只探测接口，**不会安装 Hook、修改 PowerKeeper、添加后台进程或监控线程**。即使某项显示 `present`，也只代表 DEX 中找到兼容签名，不代表旧 FCM Live 行为已经等效。探测按需从模块“操作”执行，健康检查仅读取缓存，不在每次定时检查时反复解析 APK。

## v0.4.0-alpha.5 新增跨 ROM 兼容诊断

- Magisk 操作页按已安装 APK 自动读取 PowerKeeper 接口，识别旧版及不同 ROM 的方法签名，而不是按机型/系统版本白名单截断。
- 独立报告 `present`、`variant`、`unknown`、`missing`。没有 PowerKeeper、缺少 ART、APK 不可读都保持基础 FCM 守护运行。
- 探测器仅在用户点击操作时运行，常规定时检查只读取上次报告，不增加常驻工作进程。此版本**没有集成 PowerKeeper ART Hook**，不能宣称旧 Millet Guard + FCM Live 功能已经完全等效。
- 对未识别的反射/间接 Binder 调用输出 unknown，不再误报 missing；跨 ROM 用例与离线真机探测已通过。

## v0.4.0-alpha.5 状态同步修复

修复 FCM 长连接实际在线、静态框架已加载，但 Magisk 状态因缓存时序显示 `FCM未知` 的误报。现有 5 分钟周期只在缓存无效/过期时限时调用 GcmService，健康 UI 不再修改守护进程的观察文件。正常时无额外后台查询、无重启、无清除 GMS 数据。支持任意安装机型，不引入机型版本白名单。

## v0.4.0-alpha.6 诊断误报修复

当 Magisk 显示 FCM 在线、静态框架 10/10 已加载时，操作页以前可能仍输出 `capabilities.tsv unavailable; generation may have failed`。原因是操作脚本读取了可选的 `backend/last-capabilities.tsv` 而非当前实际加载代际的 `backend/<generation>/capabilities.tsv`。新版修复报告源，历史日志独立标识；`DEX_SPLIT_INDEX_OVERFLOW` 后面的 `ADAPTIVE_OK` 和 `VERIFY_OK` 证明该次恢复成功，不应被解释为当前异常。此外只统计 PowerKeeper **实际方法** 签名，不把 APK 和类元数据计入支持数量；动态 Hook 依旧为 0，不能与框架 10/10 混为一谈。此版本并不恢复旧版 PowerKeeper Hook。
