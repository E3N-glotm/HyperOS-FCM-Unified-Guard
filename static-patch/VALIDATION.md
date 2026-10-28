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

## 尚未验收

未以新模块替换原组合，未执行加载此补丁的完整重启；尚未证明真实消息的到达率、长锁屏与网络切换表现，以及功耗是否与原组合持平或更低。

因此“单 Magisk 安装包、无需两旧模块/LSPosed”的构建与离线实现已验证；运行时等效性尚未验收，不能将本文结果宣传为替换已经成功。
