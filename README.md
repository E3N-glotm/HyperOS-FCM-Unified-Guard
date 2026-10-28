# HyperOS FCM Unified Guard · Magisk 原生 FCM 融合实验版

**简体中文 | [English](README_EN.md)**

面向 Xiaomi HyperOS 的独立 Magisk 模块，基于 [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) 的 MIT 许可实现，研究如何在**不依赖 LSPosed** 的情况下，用 Android/Magisk 可用的原生接口覆盖部分 [HyperOS FCM Live](https://github.com/E3N-glotm/HyperOS_FCM_Live) 功能。

**v0.1.1：实验版（Magisk-only，不是 FCM Live 的完全替代品）。** 后者基于 [Howard20181](https://github.com/Howard20181/HyperOS_FCM_Live) 的 GPL-3.0 项目，本仓库**没有复制其 Hook 代码**，也不声称实现相同的进程内拦截。

## 功能

| 需求 | 本模块 | 边界 |
|---|---|---|
| HyperOS Millet/Greeze 应用免冻结 | 完整复用 Millet Guard 的所有者感知白名单维护 | 不关闭整个 Millet/Greeze |
| Xiaomi GMS limiter | 在接口存在时尝试关闭，并验证 `mGmsLimitEnabled` | 不依赖硬编码 ROM 版本 |
| FCM 假在线、心跳和断线恢复 | 复用 MCS 主动心跳、DNS 分层判断、原生 GCM_RECONNECT、严格条件下的兜底恢复 | 网络不可达时不通过杀 GMS 硬修 |
| HyperOS 最近任务滑除后 `stopped=true` | 仅响应识别出的 SwipeUpClean，恢复已管理包的停止标志 | 不替代真正 Force Stop 的语义 |
| Android DeviceIdle | 新增原生豁免检查；可选仅为 GMS 增加豁免，记录本模块的变更以供卸载恢复 | 默认**只读**；部分 ROM 不支持此 API |
| FCM Live 对 `system_server` 的 Hook | **未实现** | 不能以 shell 代替 `BroadcastQueue`、`DomesticPolicyManager`、`Greeze.isAllowBroadcast` 的实时方法拦截 |
| FCM Live 对 PowerKeeper 的 Hook | **未实现** | GMS limiter 和 DeviceIdle 是部分原生替代，不能覆盖所有 PowerKeeper 内部判断 |

## 安装与迁移

1. 先保存原 Millet Guard 配置 `/data/adb/millet_guard/packages.list`，**不要删除现有稳定模块**。
2. 在 Magisk 中安装本仓库 Release 的 ZIP。独立模块 ID 为 `fcm_unified_guard`，运行目录为 `/data/adb/fcm_unified_guard`。
3. **不要与原 Millet Guard 同时运行。** 检测到原模块已启用时，本模块自动停止所有工作进程并显示冲突说明，不会争抢系统白名单。要测试本模块，应先在 Magisk 禁用原 Millet Guard，再重启。
4. 本模块安装时不会禁用 LSPosed 或 FCM Live。对比测试时由用户单独在 LSPosed 中停用 E3N FCM Live 并重启；测试前建议备份配置，做好通知延迟可恢复的准备。
5. 新模块默认只管理 `com.google.android.gms`。按需编辑 `/data/adb/fcm_unified_guard/packages.list`，每行一个 Android 包名；或者执行：

```sh
su -c '/data/adb/modules/fcm_unified_guard/bin/milletctl add com.tencent.mm'
su -c '/data/adb/modules/fcm_unified_guard/bin/milletctl status'
```

**不会自动复制旧模块的历史管理名单或进程状态**；避免把旧模块残留状态误判为本模块所有。迁移时从备份中手工选取需要的应用即可。

### 可选 DeviceIdle 原生豁免

运行配置：`/data/adb/fcm_unified_guard/unified.conf`。

```ini
# 默认只查看；不会修改 DeviceIdle
DEVICEIDLE_GMS_POLICY=observe
```

如需由本模块维护 GMS 的 DeviceIdle 豁免，可将 `observe` 改为 `enforce`，再重启。**如果 GMS 已由系统或其他程序豁免，模块不会重复修改或把该条目算成自己所有。** 卸载时仅尝试撤销本模块实际增加的条目。

## 验证方法

Magisk 点击**操作**查看连接、白名单、DeviceIdle 与 FCM 接口诊断。使用以下命令可读取已安装模块的状态：

```sh
su -c 'cat /data/adb/fcm_unified_guard/startup-status.txt'
su -c '/data/adb/modules/fcm_unified_guard/bin/milletctl status'
su -c 'dumpsys activity service com.google.android.gms/.gcm.GcmService | grep "Is client connected"'
```

**Connected 不代表微信一定实时收到消息。** 严格对比需要相同网络环境下记录锁屏多小时的端到端通知到达率、延迟、断线时长，以及 `dumpsys batterystats`、实际唤醒和耗电。未做这类 A/B 测试前，不能认定本模块比 LSPosed 组合更省电或更稳定。

## 回退与兼容

禁用本模块并重启后，可以重新启用原 Millet Guard 和原 E3N FCM Live；不要让旧新两个 Millet 写入进程同时运行。卸载时会清理本模块所有的运行进程和由它新增的白名单条目，保留配置供用户备份。不要把本实验模块描述成全量绕过 HyperOS 推送策略。

## 源码与许可

- 核心代码继承 [Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard) 的 MIT 实现，版权归 E3N；保留原始许可。
- 研究对照 [E3N HyperOS FCM Live](https://github.com/E3N-glotm/HyperOS_FCM_Live)（原作者 Howard20181，GPL-3.0），**未纳入其 Xposed/Java Hook 源码或二进制**。如果未来直接引用 GPL 代码，将遵守 GPL-3.0 的兼容要求。
- 当前仅针对已验证的 HyperOS/GMS 环境实验；不保证其他设备、ROM 或系统更新后可用。
