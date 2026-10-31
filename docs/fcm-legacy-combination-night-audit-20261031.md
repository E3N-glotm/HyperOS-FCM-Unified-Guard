# Millet Guard + E3N FCM Live → Unified Guard：夜间 FCM 对照审计（2026-10-31）

## 基准与证据边界

用户长期使用的稳定基准为 **Millet Guard v2.1.x + E3N FCM Live v1.4.1-e3n-os4**。旧 FCM Live 的实际已安装 APK 包名为 `io.github.e3n.hyperos.fcmlive`，2026-10-31 当前安装状态 **enabled=0**，故不能把旧模块视为已在现行 Unified Guard 内激活。该 APK 的 `META-INF/xposed/scope.list` 明确包含 `system` 与 `com.miui.powerkeeper`，而不只是 PowerKeeper。

旧 Millet Guard 仍存的原始 `module/bin/fcm_guard.sh` 与 Unified Guard 的代码对比表明：旧版允许在 DNS 尚未恢复时通过原生 `GCM_RECONNECT` 重建 GMS 自身的重连调度，**只有最后手段的 GMS 进程重启**受到 Android DNS、TCP 5228–5230、近期 UNKNOWN_HOST 等严格前置保护。

## 旧组合功能拆分

| 组件 | 旧版行为 | 新统一模块状态 |
|---|---|---|
| Millet/Greeze | 事件驱动维护 GMS 免冻结名单，并对 GMS 限制做专项处理 | 已实机确认名单、`mGmsLimitEnabled=false` |
| FCM MCS | GcmService 两分钟用户态轮询 + 15 分钟限制的原生 MCS 心跳，检测陈旧 NAT 连接 | 已迁移，**深度睡眠可推迟轮询** |
| Soft reconnect | 在 GMS 自身重连闹钟丢失/过期时发送原生 `GCM_RECONNECT`；不要求 DNS 正常，不杀死 GMS | alpha.8 scheduled 分支误增 DNS 前置；本次恢复旧版语义 |
| FCM Live 系统 Hook | Greeze allow/defer/limit、DomesticPolicy、广播自启动、名单/网络/AMS 权限 | 新版 10/10 静态框架已 bind-mount，**并非逐调用等效实证** |
| FCM Live PowerKeeper Hook | updateGmsAlarm/updateGmsNetWork/updateGoogleReletivesWakelock/updateFrameworkGmsNetStatus，历史 NetdExecutor.initGmsChain | Android 17 / PK 4.2.00 已无部分旧签名；现有原生运行时兼容桥接，但集成版方法级行为仍需独立实证 |
| 系统唤醒 | GMS 自带 `ELAPSED_WAKEUP` 心跳闹钟 | 实机证明确有此闹钟；夜间被严重延迟的根因未唯一确定 |

## 2026-10-31 实际断连

- 02:49 起断连至 03:37，约 48 分钟，后由统一模块软恢复。
- 06:15 起再次断连；07:16:42 的原生和备用 GMS 连接均 `Failed connection err:3`（历史 event 编码为 UNKNOWN_HOST）；07:48:13 GMS 重连闹钟报告约 36 分钟的过期延迟，07:48:14 实际恢复 MCS 连接，故第二段断连约 93 分钟。
- GMS 通过 `Android AlarmManager` 注册了确切的 `ELAPSED_WAKEUP` 心跳闹钟，且系统 DeviceIdle 白名单包含 GMS。单纯每 120 秒在 Shell 中运行 `sleep` 不可能保证 CPU 深度休眠时按期执行。
- 08:33、10:06、11:05—11:09、12:42—12:46 在 GcmService 历史中可查到多个微信 `Received / Acked / Successful broadcast`，但不能证明断连期间全部消息按时交付。

## 已实施修复

PR #19 / main `3ceab7f1bf2d91cd14c3e1084069995db242dfb7`：

1. `module/bin/fcm_guard.sh`：scheduled 状态持续断连 600 秒后可有界发送 Google 原生 `GCM_RECONNECT`，即使 Android DNS 暂时不通；间隔仍不少于 900 秒。不改网络路由、Box 规则、GMS uid、全局 443，不发送 SIGTERM，硬恢复保持独立严格 DNS+5228 保护。
2. `module/bin/unified_event_worker.sh`：在**原来单条** `logcat -b main -b events` 的标签过滤范围内添加 GMS `gtalk_connection` 事件。已有 GMS 原生连接尝试唤醒 CPU 时可及时检查连接；保留每 15 秒去抖。没有新进程、新 Alarm、新 wakelock 或高频轮询。
3. 增加 `tests/test_gtalk_single_event_worker.sh` 的真实 Shell/FIFO 事件派发回归，与已有 DNS/心跳/worker stdin 隔离测试一起通过。
4. 手机已将新脚本独立下载、与旧版 diff 审核后原子替换，**无重启**；仅事件监听器进程安全切换为新 PID，旧 PID 经身份匹配终止；三 worker、PowerKeeper/GMS、FCM 5228 均正常。

### 实机运行痕迹

- `fcm_guard.sh` 新 SHA256：`b8481dc0d8eabc92d740c7b8705b5e3878653e10242b4f2d26357b76c6bf4d1c`。
- `unified_event_worker.sh` 新 SHA256：`2064b956fd0969d73f881dc09b045f2f7c03310e8a18c72ee0bbcc4ee1e57cb94d18c7ad9c85d87464`。
- 旧脚本备份：`/data/adb/fcm_unified_guard/backups/pre_oldcombo_fix_20261031/`。
- 2026-10-31 13:56 手机：`settings pid=10752`、`maintenance pid=10760`、`events pid=11962` 身份验证通过；新事件流的 `logcat pid=11967` 已包含 `gtalk_connection:I`；FCM `ESTABLISHED :5228`，Greezer GMS limiter false，框架 ACTIVE；未新出现原生崩溃。

## 尚不能宣称旧方案等效的条件

本轮只是恢复了明确的软恢复功能差异与自然事件触发机制。Android 的系统 sleep、GMS 本身的恢复闹钟行为、国内移动网络/DNS（手机当前 Box 的 `fcm` DNS tag 与 `local/remote` 都指向 `223.5.5.5`，没有独立的备用上游）都可能影响最终可达性，**没有足够证据认为是某一个因素唯一导致 93 分钟断连**。

下一轮必须有自然锁屏/蜂窝夜间对照，分别采集断连发生时间、首次可运行守护时间、GMS native alarm 延迟、Android resolver/专用 FCM TCP 可达性、微信实际成功广播与待机耗电；若再次发生超长睡眠，应先处理有效系统唤醒保障，而非继续缩小 Shell sleep 周期。旧 FCM Live 的 system_server / PowerKeeper 动态 Hook 与现在的静态10/10及原生运行时 Hook，仍需针对调用/参数语义做对等审计。

本修复暂不改写已经发布的 v0.4.0-alpha.8 ZIP，当前手机仍显示 alpha.7 + 安全热补丁；下一次正式整合发布前需完整集成 CI 与跨 ROM / 实机重启验证。
