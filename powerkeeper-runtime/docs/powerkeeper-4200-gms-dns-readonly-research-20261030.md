# PowerKeeper 4.2.00：GMS DNS 与原生限制路径审计（2026-10-30）

> 仅记录只读固件分析和测试结论；本文不是功能开启指引，也不代表已经达到旧模块组合的 FCM 送达率或功耗。
> 实验分支 `feat/powerkeeper-runtime-old-new`，PR #15；未经实机验证的功能不得进入正式发布包。

## 已验证的运行基线

- 目标 ROM：Android 17 / HyperOS 4，`com.miui.powerkeeper` `versionName=4.2.00`、`versionCode=40200`；代码签名来自已安装的 `/system_ext/app/PowerKeeper/PowerKeeper.apk`，而非网上同名 APK。
- 单次 Zygisk Native + Java 实验已证明：`preAppSpecialize`、`postAppSpecialize`、ART 初始化、`Application.attach` 均实际进入；`GmsObserver.updateFrameworkGmsNetStatus` 与 `GlobalFeatureConfigureHelper.getDozeWhiteListApps(Bundle)` 两个 Hook 安装成功且执行了一次。
- **不能据此证明推送等效**。同一实验中 Greeze 报告 `mGmsLimitEnabled=true`；FCM TCP/5228 虽为 ESTABLISHED，但没有真实端到端投递成功率或跨天续航对照。
- 实验模块已通过第二次重启恢复为 disabled、Zygisk Next 未登记、PowerKeeper maps 无实验库，tombstone 保持原计数。生产构建无需 LSPosed。

## 只读 DEX 逆向：新旧接口

| 所属类 / 接口 | 本固件确认签名 | 证据与风险 | 实现策略 |
|---|---|---|---|
| `GmsObserver.updateFrameworkGmsNetStatus` | `(Z)Z`，包可见 | 通过反射调用 `IGreezeManager.updateGmsNetStatus(boolean)` 后读取当前值；传 `false` 并不保证 Binder 接受，也不等于 `mGmsLimitEnabled` 已被解除 | 已测试 Hook；有效性另查真实 Greeze 状态，不以调用成功为准 |
| `GlobalFeatureConfigureHelper.getDozeWhiteListApps` | `(Bundle)List` 与 `(Context)List` | 仅 Bundle 重载在此次运行中有 Hook 与调用证据 | 保留 OEM 原列表、只增加 GMS，后续可评估 Context 重载 |
| `NetdExecutor.initGmsChain` | 当前 APK 无该签名 | 旧版专用 | 仅在其他 ROM 上动态存在且签名相符时处理 |
| `NetdExecutor.setGmsDnsBlockerState` | `(IZ)V`，public static synchronized | DEX 原始指令：布尔真 → `deny`，布尔假 → `allow`；通过 `dnsproxyd` 的 `setuiddnsrule` 下发，首个整型参数为目标 UID | 新增 **默认关闭** 的试验接口，仅语义明确并动态解析 GMS UID 后允许精确更改对应 UID 的 `deny`；其他 UID / 允许规则原样转发 |
| `GmsCoreUtils.setGmsCoreState` | `(Context,I)V` | 源代码直接调用 `PackageManager.setApplicationEnabledSetting`，特定状态还触发 `killGmsCoreProcess` | **禁止在 FCM 保活 Hook 中直接修改**：避免禁用/反复重启谷歌应用 |
| 旧版 `updateGmsAlarm/updateGmsNetWork/updateGoogleReletivesWakelock` | 当前 APK 中不存在 | 旧版历史接口 | 保持旧 ROM 兼容策略、只按实际反射签名启用 |

`setGmsDnsBlockerState(IZ)V` DEX 证据包含：`if-eqz` 选择 `deny` 或 `allow`，随后调用 `NetdExecutor.execute`，命令字符串为 `dnsproxyd`、`setuiddnsrule`。因此 **不能只凭方法名就对任意 ROM 开启 Hook**，必须同时确认语义和 GMS UID，且不能通过固定 UID 适配不同用户空间或机型。

## 本轮代码改进

1. `PowerKeeperRuntimePolicy.install(loader,candidates,hooks)` 的旧入口保持原行为；DNS 新候选只报告 `candidate_unverified`，**不安装 Hook**。
2. 增加实验重载 `install(...,verifiedGmsUid,verifiedGmsDnsSemantics)`，满足有效 GMS UID、确认的签名语义后才注册，运行时严格比较目标 UID；对于其他 UID 原参数、原行为不变。
3. 宿主回归新增：默认拒绝、UID 缺失时拒绝、正确 GMS UID deny→allow、其他 UID deny 不变、已有 allow 保持且原 OEM 方法仍被执行。
4. Java 端一次性方法审计只在原生 Zygisk 实验编译宏提供专用标记时开启，避免未来普通/正式构建无意执行每次启动的额外文件写入。

**注意**：实验重载目前还没有来自 ROM DEX 签名语义验证器的可信调用点，因此 DNS 候选维持关闭；CI 通过仅能证明逻辑可编译和模拟参数正确，不能代表真机 DNS 行为。

## Millet / Greeze 根因和旧版等效范围

`Settings.System.MILLET_NO_RESTRICT_APP` 是 Greeze 冻结策略的另一条输入路径，并非 DeviceIdle 白名单。只保护 `getDozeWhiteListApps` 不能替代 Millet 免冻结。PowerKeeper 4.2.00 的独立分析表明，`ActiveStateController.dealNoRestrictApp()` 可从内部 `UserConfigure` 表重建该 Settings 字段，丢弃此前仅在下游插入的 GMS 条目。具体参考 [PowerKeeper 4.2.00 白名单重写调查](https://github.com/dingwen07/hyperos-fcm-fix/blob/main/docs/xiaomi-millet-no-restrict-app-rewrite-investigation.md)。

旧版 [HyperOS Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) 采用 Settings 事件驱动同步与低频兜底，另有依据 GMS 原生 `GcmService` 的 FCM 诊断、自恢复与最小化网络例外。单一 Magisk 模块必须分别维持：
- Millet/Greeze 白名单**实际成员资格**（不清空其他应用、不持续重写私有数据库）；
- PowerKeeper Java Hook（无类 / 方法不兼容时独立降级）；
- 网络 DNS/规则只对 GMS UID 且有明确证据时修改，绝不全局关闭网络限制；
- FCM 真消息送达、原生心跳 / NAT 存活、网络恢复路径及后台功耗。

## 下一步测试门槛

- 在具备备用机/回退通道时，对新 DNS UID 候选先只记录调用参数与真实 GMS UID；不得立即启用行为修改。
- 证明该 UID 确实是 `com.google.android.gms` 当前 userId 的 UID、API 字节码语义匹配，而且 `dnsproxyd` 原本在对其下发 `deny`，再考虑单次受控改写测试。
- 校验 `mGmsLimitEnabled`、`MILLET_NO_RESTRICT_APP`、GMS UID 级联网规则的前后状态，并进行有真值的通知送达对照；不能把 5228 ESTAB 当作推送成功。
- 在多个实际 ROM 上使用类名+参数+返回值+语义证据匹配；不使用 pudding / Android 17 的硬编码开关。只有实测完成，才能评价是否可放入正式统一模块。

## 可复核的只读命令

```sh
pm path com.miui.powerkeeper
dumpsys package com.miui.powerkeeper | grep -E 'versionName|versionCode'
/apex/com.android.art/bin/dexdump /system_ext/app/PowerKeeper/PowerKeeper.apk |
    grep -A 45 "name          : 'setGmsDnsBlockerState'"
settings --user 0 get system MILLET_NO_RESTRICT_APP
dumpsys greezer | grep 'mGmsLimitEnabled'
ss -tn | grep ':5228'
```
