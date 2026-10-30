# FCM Unified Guard 与历史双模块功能等效性核对（2026-10-30）

此文档比较原 **HyperOS-Millet-Guard v2.1.4 + E3N HyperOS_FCM_Live** 与当前纯 Magisk Unified Guard 静态策略。不要把状态栏的 **10/10** 宣称成旧 LSPosed 全部 Hook 已覆盖；10/10 仅是 `services.jar` / `miui-services.jar` 内定义的十个能力键。

## 已实现或保留

| 功能 | 原方案 | Unified Guard | 差异 |
|---|---|---|---|
| `MILLET_NO_RESTRICT_APP` 托管名单 | Millet Guard reconcile | reconcile | 新版新增 SettingsProvider fail-closed，避免 Binder 异常误写白名单 |
| GMS OEM limiter / DeviceIdle | Millet Guard + Live | reconcile / deviceidle | 按手机可用接口执行，非通用保证 |
| 断联检测、MCS 主动心跳、断线计时 | Millet Guard fcm_guard | fcm_guard | 保留；alpha.3 修复规范域名误判与卡住的 scheduled-alarm 软恢复 |
| FCM UID TCP 5228–5230 Box 例外 | Millet Guard | fcm_guard | 保留，需检测具体 Box 规则 |
| 设置监听、维护轮询、GMS 事件、SwipeUpClean | 各独立 Shell | 合并工作进程 | 可减少重复订阅，但不是功耗对照证明 |
| Greeze 广播放行/延迟、DomesticPolicy、广播自启动、AMS 临时豁免 | Live system_server Hook | 静态 services/miui-services | 具备结构映射；不等于所有 ROM 运行时行为一致 |
| ListAppsManager 黑名单和白名单 | Live 支持 `mSystemBlackList/SYSTEM_BLACK_LIST` 与 `mUseDataWhiteList/USE_DATA_WHITE_LIST` | alpha.3 静态只接受大写字段 | **历史兼容回退遗漏；本次修复源码已恢复双命名兼容** |
| GMS limiter 方法 | Live 优先 `triggerGMSLimitAction(boolean)`，回退无参 | alpha.3 静态只接受无参 | **历史重载适配遗漏；本次源码已支持 boolean 入参** |

## 仍然缺失的 PowerKeeper 进程 Hook（独立于 10/10）

旧版 E3N FCM Live 的 `Hooker.onPackageReady("com.miui.powerkeeper")` 会针对：

1. `com.miui.powerkeeper.utils.GmsObserver.updateGmsAlarm(boolean)`
2. `GmsObserver.updateGmsNetWork(boolean)`
3. `GmsObserver.updateGoogleReletivesWakelock(boolean)`
4. `GmsObserver.updateFrameworkGmsNetStatus(boolean)`
5. 可选 `com.miui.powerkeeper.utils.NetdExecutor.initGmsChain(...)`：将动作调整为 `ACCEPT`
6. `com.miui.powerkeeper.provider.GlobalFeatureConfigureHelper.getDozeWhiteListApps(Bundle)`：追加 GMS

这些是 **PowerKeeper APK 内部的运行时 Hook**。当前 Unified Guard 的静态构建仅针对 framework JAR；Magisk 维护 DeviceIdle 白名单、Box 端口例外，**不能等同于**四个 `GmsObserver` 状态转换或 PowerKeeper 自有防火墙的入口替换。

不能直接修改 APK 的 classes.dex 并宣称无损替换：安卓 APK 签名、priv-app 授权、ART/OAT、SELinux、覆盖路径、厂商安全启动及 OTA 兼容都须分别验证；修改 APK 可能造成 PowerKeeper 无法启动或系统服务异常。因此目前**未将未经验证的 PowerKeeper APK 修改接入正式安装流程**。

## 继续研发的验证协议

- 通过设备侧只读抓取 PowerKeeper 的实际 APK/odex/class 列表、方法签名、当前 GMS 链状态，以及当前模块 `backend/state`、`capabilities.tsv`；按设备和 ROM 记录证据。
- 对每个 PowerKeeper 行为定义独立的必要性与副作用测试：是否确实阻断 FCM、单次限制后如何恢复、被覆盖的权限与资源、在整机待机上的功耗影响。
- 优先查找可公开调用的 PowerKeeper 原生命令或一次性配置接口；只在证明不能等效且安全时考虑其他实现方式。
- 若进入静态 APK patch 实验，必须使用真实 OEM APK 副本、签名与 SELinux 检查、安装前安全回退、冷启动测试；功能缺失时按单项降级，**不能因为 10/10 JAR 校验通过就报“完全等效”**。
- 稳定性对照用同网络/同 ROM/同电池统计窗口，对比双模块基线与纯 Magisk 的 GCM 断联分钟数、真实消息延迟、PowerKeeper 限制命中次数及待机耗电。单次 `Is client connected: true` 不代表消息可达。

## 本次用户实际问题与临时策略

2026-10-30 用户连续断联接近 7h，原因包含 `ping mtalk.google.com` 输出 canonical `mobile-gtalk.l.google.com` 导致 Guard DNS 误判；一次原生 GCM_RECONNECT 使 GMS PID 不变而连接恢复。已在 alpha.3 修正解析及软恢复，**但这不消除上述 PowerKeeper 等效性缺口**。

若对端消息可靠性优先且新方案多次复现真实丢推送，先保留双模块作为可回退基线；不要同一时间同时启用两套后台守护与重复 LSPosed Hook。
