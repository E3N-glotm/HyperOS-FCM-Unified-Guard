# 纯 Magisk 静态补丁候选版 v0.3.0-alpha.3

这是与 v0.2.0 并列的实验构建路径，目标是仅安装一个 Magisk ZIP，即可卸载旧 Millet Guard 和 E3N FCM Live，且不依赖 LSPosed、Zygisk 或另外安装的 APK。当前没有替换主分支的 v0.2.0 发布包。

## 实现范围

| 原有作用 | 静态候选版实现 |
| --- | --- |
| Millet 白名单、GMS 额外限制处理、DNS/心跳/重连、SwipeUpClean | 复用已经优化过的统一守护核心 |
| Greeze 放行 GMS 发出的 FCM RECEIVE | 在原判断前增加相同的 GMS 来源与 action 条件 |
| GMS 心跳、连接事件和重连广播不延迟 | 精确修改 Greeze / DomesticPolicyManager 对应判断 |
| FCM 接收应用的自启动判断 | 仅 GMS + C2DM RECEIVE 走放行，其他广播保留原逻辑 |
| ProcessPolicy、数据/网络名单 | 保留 GMS 和 persistent 进程的对应豁免 |
| AMS 广播的短时后台唤醒与 stopped 标志处理 | 保留旧 FCM Live 的来源核验、INCLUDE_STOPPED_PACKAGES 和 2000ms 临时豁免 |
| PowerKeeper 的 GMS 限制 Hook | 在它最终调用的系统端限制动作上保持 mGmsLimitEnabled=false；PowerKeeper APK 不改签名 |
| PowerKeeper GMS Doze 名单 Hook | 使用 Android 原生持久 DeviceIdle 用户豁免，保留已有豁免的所有权 |

PowerKeeper 内部上报的网络状态值不要求与旧 Hook 完全相同；候选版接替的是它通过 Greeze 施加限制的实际效果。该替代是否在长时间运行中等效，仍需实测。

## 构建与兼容性

alpha.3 取消机型、Android API 数字、ROM 版本号和预置原厂哈希白名单。安装器会查找可用 ART 虚拟机，从系统类路径及 system/system_ext/product 的标准框架目录发现 OEM JAR，再检查当前框架的必需类、字段类型、十项目标方法签名、实例方法形式和可用寄存器。全部命中且无歧义后，才根据本机文件生成补丁，并完成 DEX、ZIP 和 ART 检查。

这意味着接口相同的不同机型或系统构建无需逐个加入名单，并不代表任意 ROM 都有这些接口。目前后端仍针对 Greeze、DomesticPolicyManager、PowerKeeper 最终限制路径等 OEM 实现；缺失或改变相关实现时明确拒绝完整模式，不静默降级。相同方法签名也不能证明内部语义完全相同，其他 ROM 仍需实机消息和启动验证。

```sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
bash static-patch/test-boot-guard.sh
bash static-patch/test-capabilities.sh
bash static-patch/test-install.sh
python static-patch/package.py
```

构建使用 SDK 自带的 smali-dexlib2、smali-util、Guava 与 d8；不读取系统代理，不在手机运行期间联网下载代码。ZIP 不包含厂商原始/修改后 JAR：安装时在本机生成两个修改后文件，完成 DEX 重解析、ZIP 对齐与 ART 类加载检查后才保留。

## 启动与恢复

模块使用 skip_mount 和 post-fs-data 中的显式绑定挂载，在 system_server 启动前完成；不直接写系统分区。profile.conf 的文件路径、原文件/生成文件哈希和 ROM 状态摘要均由安装器当场记录，不是源码中的机型或版本名单。每次完整开机核对这份安装记录；OTA 或文件变化时旧补丁停用，重新安装同一 ZIP 即可重新检测并生成，不需要作者添加版本号。重新检测仍可能因接口不兼容而失败。

绑定两份文件时若第二份失败，会撤回第一份挂载。挂载前写入启动待确认标志；正常进入 Android 并完成启动检查后清除。若上次完整启动未确认，下一次完整开机自动停用这个模块。软重启 system_server 不会重新执行此保护，不能因此宣称绝对不会开机异常。

禁用模块并完整重启即可恢复原厂框架；设备上的旧模块配置和 APK 备份应在迁移前保留。安装器本身不卸载旧模块，也不操作 LSPosed 数据库。实际切换验收需要移除/停用旧核心及旧 FCM Live，避免测试结果被旧实现掩盖。

升级静态候选版时，先禁用旧静态后端并完整重启，再安装新 ZIP。安装器发现已经加入本策略的 JAR 会拒绝再次修改，不在正在使用的框架上叠加补丁。安装时源文件或 ROM 状态发生变化也会拒绝接受生成结果。

## 已完成和待完成的验证

alpha.3 已通过 34 项策略边界检查、完整结构合成框架接受和六类不兼容框架拒绝、十种开机保护场景、路径发现/别名/歧义/配置完整性检查，以及完整安装流程的六种模拟场景。Linux 测试覆盖真实符号链接别名；安装流程模拟中的 VM 返回值只验证安装控制流，不冒充真实 ART 检查。

alpha.3 尚未在手机上完成离线生成或冷启动，本轮设备连接不可用；当前设备继续运行已经验收的 alpha.2。下面的首次实机验证属于 alpha.1/alpha.2，不能当作 alpha.3 或跨机型验证。

34 项策略边界检查通过，另有返回分支目标、未知方法保持不变、缺失 OEM 字段拒绝等字节码回归；10 个方法命中，ART 独立进程能够加载全部目标类，临时豁免 API 签名已核对。2026-10-29 首次替换冷启动通过，两份补丁在 system_server 的挂载、内存映射与哈希一致；旧 Millet Guard 已禁用，当前 LSPosed 日志未发现 FCM Live 加载。GCM 在线，主动心跳前后收发流计数均递增且连接次数不变，尚非端到端应用消息验收。

alpha.2 修复首次实机验收发现的事件 FIFO 标准输入继承问题：SELinux 会阻止 system_server 接收 adb_data_file FIFO，导致 settings 等 Binder shell 命令失败。四条事件分发路径显式使用 /dev/null，不放宽 SELinux；手机已热更新两条监听脚本并验证配置事件成功，框架补丁无需重启。新增真实事件循环的四路径回归，旧代码可触发失败。

还未完成数小时锁屏、无微信进程、最近任务清理、Wi-Fi/蜂窝切换、端到端真实推送，以及同条件电池 A/B 测试。因此本版仍为候选版，不能宣传已经等效、更省电或零延迟。此路线的预期收益是取消 FCM 专用 LSPosed 运行依赖和每次方法进入的通用 Hook 框架分发；设备上若还有其他 LSPosed 模块，整机框架开销不会因本模块而全部消失。

## 许可与来源

静态策略源于 Howard20181 的 HyperOS_FCM_Live 与 E3N HyperOS 4 修复分支，相关源码按 GPL-3.0-only 提供，完整许可证见 ../bridge-source/LICENSE；已有统一守护核心保留原 MIT 许可。安装包附带两份许可证。静态修补思路也参考了 biplobsd/fcm_notification_fix，但本目录未直接复制其补丁实现或附加通知功能。
