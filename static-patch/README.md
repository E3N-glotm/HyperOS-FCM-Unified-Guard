# 纯 Magisk 静态补丁候选版 v0.3.0-alpha.1

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

当前只允许 Xiaomi pudding、Android API 37、OS4.0.5.0.XPCCNXM，以及 profile.conf 记录的两个原厂 JAR SHA-256。不同构建拒绝安装，不套用旧补丁。

```sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
bash static-patch/test-boot-guard.sh
python static-patch/package.py
```

构建使用 SDK 自带的 smali-dexlib2、smali-util、Guava 与 d8；不读取系统代理，不在手机运行期间联网下载代码。ZIP 不包含厂商原始/修改后 JAR：安装时在本机生成两个修改后文件，完成 DEX 重解析、ZIP 对齐与 ART 类加载检查后才保留。

## 启动与恢复

模块使用 skip_mount 和 post-fs-data 中的显式绑定挂载，在 system_server 启动前完成；不直接写系统分区。每次完整开机重新检查原厂文件、ROM 与补丁哈希。任一检查不符则停用，不挂载补丁。

绑定两份文件时若第二份失败，会撤回第一份挂载。挂载前写入启动待确认标志；正常进入 Android 并完成启动检查后清除。若上次完整启动未确认，下一次完整开机自动停用这个模块。软重启 system_server 不会重新执行此保护，不能因此宣称绝对不会开机异常。

禁用模块并完整重启即可恢复原厂框架；设备上的旧模块配置和 APK 备份应在迁移前保留。安装器本身不卸载旧模块，也不操作 LSPosed 数据库。实际切换验收需要移除/停用旧核心及旧 FCM Live，避免测试结果被旧实现掩盖。

## 已完成和待完成的验证

已在当前手机临时目录生成候选补丁，未挂载到正在使用的系统。34 项策略边界检查通过，另有返回分支目标、未知方法保持不变、缺失 OEM 字段拒绝等字节码回归；首轮 10 个方法命中，ART 独立进程能够加载全部目标类，临时豁免 API 签名已核对。

还未完成替换后的冷启动、数小时锁屏、无微信进程、最近任务清理、Wi-Fi/蜂窝切换、端到端真实推送，以及同条件电池 A/B 测试。因此本版仅为候选版，不能宣传已经等效、更省电或零延迟。此路线的预期收益是取消 FCM 专用 LSPosed 运行依赖和每次方法进入的通用 Hook 框架分发；设备上若还有其他 LSPosed 模块，整机框架开销不会因本模块而全部消失。

## 许可与来源

静态策略源于 Howard20181 的 HyperOS_FCM_Live 与 E3N HyperOS 4 修复分支，相关源码按 GPL-3.0-only 提供，完整许可证见 ../bridge-source/LICENSE；已有统一守护核心保留原 MIT 许可。安装包附带两份许可证。静态修补思路也参考了 biplobsd/fcm_notification_fix，但本目录未直接复制其补丁实现或附加通知功能。
