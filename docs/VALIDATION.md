# v0.2.0 验证记录

## 已完成的可复现验证

- Windows DevSpace 工作区：对全部 shell 脚本运行 `sh -n`。
- 行为回归：FCM 正常连接仅一次 GcmService 状态读取；主动心跳暴露 stale MCS 后进行第二次读取并进入恢复；状态未知时不误干预。
- 白名单、进程所有者锁、DeviceIdle 模式、SwipeUpClean 作用域、worker PID + start-time 身份校验全部通过现有自动化测试。
- 桥接二进制使用先前 Android 设备已安装并实际注册 Hook 的 E3N FCM Live v1.4.1-e3n-os4，打包时验证 SHA-256；不更改签名，也不修改 LSPosed 作用域。
- 2026-10-28 在 Xiaomi pudding / HyperOS 4 / Android 17：实机恢复原 Millet Guard `packages.list` 和 `managed.last`，禁用旧模块后启动融合核心。只按确切原模块命令行验证并终止旧 worker，确认仅新 `settings_worker.sh`、`maintenance_worker.sh`、`unified_event_worker.sh` 三个持久工作进程；原有 Millet 白名单条目保留，GcmService 仍报告连接。
- LSPosed 日志对当前进程 PID 显示 `system_server` 的 Greeze 广播相关 Hook，以及 PowerKeeper `GmsObserver.updateFrameworkGmsNetStatus` Hook 已注册。
- 迁移中发现一份旧版进程树枚举可能包含 PID 1 和无关服务。**不允许按该文件执行任何 kill**。已改为仅针对五个经过 PID/命令行双重验证的旧模块工作进程，且拒绝 PID 1/2。

## 仍需实测的内容

- 冷启动后持续运行与 LSPosed 当前 PID Hook 注册状态。
- 在相同网络和工作负载下，对比旧双模块与新版的 1 小时以上进程 CPU ticks、唤醒、内存和整机耗电。
- 锁屏、Wi-Fi/蜂窝切换、微信没有进程与最近任务滑除后的真实消息到达率；FCM `Connected` 不能证明端到端到达。
- 任何未经现场验证的新设备和 ROM。

因此该版本标记为 **实验版**；不能宣传为“不依赖 LSPosed”“功耗已降低”或“推送零延迟”。
