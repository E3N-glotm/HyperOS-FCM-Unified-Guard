# 2026-10-29 静态候选版验证

目标：Xiaomi pudding / SDK 37 / OS4.0.5.0.XPCCNXM。

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
