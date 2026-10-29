# 2026-10-29 静态候选版验证

## v0.4.0-alpha.1：按功能降级、状态灯与自动重建

当前行为已取代 alpha.3 的严格安装拒绝与手动重装流程：安装仅在模块/配置目录无法写入时中止；缺 ART/OEM 或个别接口仍可安装。基础核心不以静态后端为启动条件，模块不自动创建 disable/remove，也不自动重启。Magisk 名称/描述显示绿黄红状态，操作按钮显示逐项原因并重试适配。

生成器独立规划十项静态功能，缺少某个字段只降低对应功能；ART 接口失败可排除该功能后再生成其他能力。无 OEM JAR 或其 DEX 不可用时仍尝试服务端可用能力。基础 FCM 恢复不再要求必须有 sing-box 进程。

每次开机仅快速核对本机缓存与当前文件；源文件变化后先正常启动系统及基础守护，再自动重建，下一次正常重启加载，不需要重新刷 ZIP。源/输出哈希均为运行时摘要，供缓存身份和损坏检查使用，不是安装白名单。旧框架不会覆盖到不同的新框架上；生成/挂载失败或上次未确认启动只影响后端，不禁用整个模块。SELinux 标签不可用时同样保留基础模式。

已验证：34 项策略边界、原有严格契约/字节码回归、全量/部分/OEM 缺失/ART 排除/损坏 OEM 五类自适应计划；Linux 流程覆盖宽松安装、配置保留、核心独立启动、状态颜色、自动 OTA 重建、挂载回退、单缓存隔离、失败限频、生成竞争和等待重启时再次操作。流程测试模拟 VM 与挂载，不冒充真实 OTA。

最终 Linux 流程共 18 项通过；另外确认错误的 SELinux 标签不会被接受为可挂载缓存，也不会导致整个模块禁用。最终本地 ZIP SHA-256 为 e858148ff3ae73678515fe934a02e218503e76bda24a8c8762e1cfb89cc834b7，手机 Download 副本按同一摘要校验；CI 编译环境生成的包以其伴随的 .sha256 为准。

手机实测在 /data/local/tmp/fcmu-adaptive-v04 隔离目录进行，活动 alpha.2 与系统挂载未改动。完整 ZIP 的 customize.sh 安装流程成功并迁移出 legacy 缓存，未创建 disable/remove。ZIP 内完整生成器对当前 ROM 原厂文件生成 10/10 项能力，DEX 对齐及逐项 ART 检查通过，结果哈希仍为 services=021312744b7766102ccf9045b567d2bcd6cc9634a203bc21c15bd4490ab89cf3、miui-services=0a96c4f1c8f672ff76c84ef7c6ed4da11ef537420a70a811f638b36311dfe6f1。新诊断脚本在独立目录验证状态文件/模块描述，不宣称 Magisk 已加载新模块。

尚未实测：安装 0.4.0-alpha.1 后的完整冷启动、真实 ROM OTA 后的自动重建及下一次启动、其他机型和端到端推送/耗电 A/B。当前版本实际名为 0.4.0-alpha.1，旧记录中的 alpha.1/alpha.2/alpha.3 均属于 0.3.0 历史阶段。以下保留历史证据，不能当作本轮完整运行验收。

目标：Xiaomi pudding / SDK 37 / OS4.0.5.0.XPCCNXM。

上述设备是历史实测对象，不是 alpha.3 的安装白名单。

## alpha.3 能力检测改造

- 生产安装/启动代码取消 TARGET_DEVICE/TARGET_SDK/TARGET_BUILD 和预置原厂 SHA-256，改为安装时结构探测并动态记录 profile；不同机型或构建只要满足同一契约即可进入生成与 ART 检查。
- 增加只读 Patcher --probe，检查必需类、字段、签名、实例方法、寄存器和重复类；同一 probe 也在生成器入口执行，避免绕过安装器直接生成时漏检。
- OEM JAR 根据当前类路径和标准分区位置发现；真实路径别名去重，多份不同文件时拒绝猜测。ART 可执行文件动态发现。
- 结构合成测试：完整契约通过；缺类、签名变化、字段缺失、静态方法误配、重复类、已打补丁六类拒绝。原 34 项策略与字节码边界测试继续通过。
- 启动保护十场景通过，包含任意安装身份/版本数字、不同框架目录、OTA、源文件及补丁损坏、未确认启动和部分挂载回退。Linux 路径检测测试通过真实符号链接别名与歧义检查。
- 安装控制流六场景通过：任意 ROM 标识、不同分区布局可安装；缺目标、生成失败、模拟 ART 拒绝和生成期间 ROM 变化均在接受前中止。这里使用模拟 VM 测试控制流，不能替代手机真实 ART 校验。

本轮手机 MCP 连接失败，本地 ADB 无设备，未改动手机正在运行的 alpha.2，也未完成 alpha.3 的本机离线生成、安装或冷启动。尚无第二款机型/ROM 的实测资料，不能宣传任意系统通用。后续章节中的安装、ART 与冷启动结果为 alpha.1/alpha.2 历史证据。

手机通过完整 ZIP 在 /data/local/tmp/fcmu-static-analysis/install-candidate 完成隔离安装，退出码 0；配置定向到独立 install-runtime，未调用 post-fs-data 挂载或 service，活动模块保持原状。

实测 ZIP SHA-256：
c9f846f47e33a421a8e2a7bab1daaa35e6ba4828092a0f910cbcb721309cfa03

该包的补丁生成器 SHA-256：
67de50cae4d9856017138d5da7f1519068e69ce60449a5045c1c415a2015db42

策略 DEX SHA-256：
f2b78b295bd613f02081a7c952023800ab28dd85948461fdea26ffd3b8eb55dc

## 已通过

- 完整安装器生成两个框架文件，10 个预期方法各命中一次，DEX 重解析成功。
- services.jar 的 5 个 DEX 与 miui-services.jar 的 2 个 DEX 均为 STORED，并通过 4 字节数据偏移对齐检查。
- ART -Xverify:all 独立进程加载 StaticPolicy、AMS、BroadcastQueueModernStubImpl、ProcessPolicy、GreezeManagerService、DomesticPolicyManager、ListAppsManager、AwareResourceControl 成功。
- Android 17 实机 PowerExemptionManager 构造器和 2000ms 临时豁免方法签名检查成功。
- 34 项策略边界测试；返回分支不会绕过注入、非目标方法不修改、缺失原厂字段拒绝等字节码回归。
- 5 种启动保护情况：成功挂载、OTA 构建变化、原文件哈希变化、上次未确认启动、第二份挂载失败后撤回第一份。
- 旧统一核心的全部行为回归通过。
- ZIP 不含 APK、bridge 目录、Zygisk 库与预制厂商 JAR，手机 Shell 语法检查通过。

验证后 /system/framework/services.jar 和 /system_ext/framework/miui-services.jar 的 SHA-256 仍为原厂值。旧 Millet Guard 启用，Unified Guard 禁用，GcmService 的 Is client connected 为 true。

## 首次替换后的实机验收（2026-10-29，alpha.2 修复）

用户安装 alpha.1、关闭旧模块并完成冷启动后检查：

- sys.boot_completed=1，启动状态 BOOT_OK，两份 JAR 同时存在于 system_server 挂载与内存映射，挂载文件 SHA-256 与模块生成文件及 profile 一致。
- 旧 Millet Guard disable 存在，无旧模块脚本；millet_monitor 的可执行文件是 /system_ext/bin/millet_monitor，属于系统原有进程，不作为旧模块残留。
- 当前开机 LSPosed 的模块与 verbose 日志未发现 FCM Live；其他 LSPosed 模块仍在运行，不能声称整机已经移除 LSPosed 开销。
- Greeze mGmsLimitEnabled=false，GMS 获得 NO_RESTRICT_APP 保护，GMS 和微信原生 DeviceIdle 豁免存在。
- GcmService connected=true，主动 MCS 心跳使 streamId 从 3/2 递增到 4/3，connects=1 未变化；没有以此冒充应用消息到达证明。
- 当前 crash 缓冲区为空，检查窗口未发现 StaticPolicy 的链接、验证和系统进程崩溃错误；反射分支未执行或异常被捕获的情况仍不能凭日志完全排除。

发现并修复真实 bug：settings 监听子命令继承私有 FIFO 作为 stdin，SELinux 记录 system_server 对 adb_data_file:fifo_file 的 read 拒绝，Binder 随后报 Failed transaction。手机上同一命令继承 FIFO 可复现，重定向 /dev/null 成功。alpha.2 对 settings/config/SwipeUpClean/GMS 事件四处分发统一显式隔离 stdin；不修改 SELinux。备份脚本后热更新并重启守护工作进程，实际配置事件更新 managed.last 成功，配置内容已恢复。九组核心回归通过；新增四路径实际循环测试在旧代码失败、修复后通过。

## 仍未验收

尚未证明真实消息的到达率、长锁屏与网络切换表现，以及功耗是否与原组合持平或更低。本轮检查时手机亮屏、远程控制与 MCP 持有唤醒锁，batterystats 起点早于本次重启并混入旧组合数据，不能用于新模块的电池 A/B 结论。

因此单 Magisk 构建、首次冷启动、连接和免冻结状态已通过初步检查；运行时完整等效性与续航仍未验收，不能将本文结果宣传为全面替换验收成功。上文隔离安装包和生成器哈希是 alpha.1 的历史记录，alpha.2 包哈希以对应构建产物为准。
