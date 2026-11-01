# alpha10：锁屏深度休眠期间的 FCM 唤醒与重连修复（2026-11-01）

## 问题及旧双模块差异

- v0.4.0-alpha.9 的维护任务使用 shell sleep(120)，在深度休眠期间不保证唤醒 CPU，无法仅靠缩短周期解决夜间长时间无检查的问题。
- 旧 Millet Guard 也使用两分钟 sleep 和 GMS 闹钟事件监听；其与旧 FCM Live LSPosed 模块联合运行时还对 GmsObserver、Greeze、DomesticPolicyManager 等做动态 Hook。当前单模块的 PowerKeeper 原生 Zygisk 映射并不自动证明这些方法级 Hook 等效。
- 2026-11-01 的实机记录包含 04:55:50 断连、05:37 软重连、05:38:47 endpoint-unavailable、06:09 再断连及 06:15 GMS 恢复；仅观察到 connected=true 或 FCM Diagnose 连接计时清零都不足以证明连续正常投递。

## alpha10 实现

- 新增独立 ARM64 静态二进制 `bin/fcmu_alarm_wait`，基于 Linux `timerfd_create(CLOCK_BOOTTIME_ALARM)`，无需常驻唤醒锁，计时器由内核 alarmtimer 唤醒 CPU 后结束。
- 在支持 CAP_WAKE_ALARM / alarmtimer 的设备上，维护任务保持正常连接 120 秒检查、已观测断连 30 秒检查；不会每 30 秒持续主动唤醒处于正常状态的设备。
- 不支持的内核或非 ARM64 系统自动降级到原有 shell sleep；健康状态明确报告 `WAKEUP` 及最近一次计时器触发时间，不能把降级误报为可主动唤醒。
- 原生 `GCM_RECONNECT` 软恢复在断连 90～120 秒可触发，保留 3～5 分钟请求限频；仅在确有 MCS 连接端点时清除故障状态。
- MCS 主动心跳间隔从 900 秒缩短为 600 秒，保持 DNS/TCP 可达后才允许 GMS 进程级兜底重启。
- 不依赖 LSPosed；不禁用系统全局网络策略、不修改用户应用数据。

## 构建

源文件：`native/fcmu_alarm_wait.c`。在已安装 Clang/LLD 的 Linux 上执行：

```sh
clang --target=aarch64-linux-gnu -fuse-ld=lld -nostdlib -static \
  -fno-stack-protector -fno-pie -no-pie -Wl,-e,_start \
  -Wl,--gc-sections -Wl,--build-id=none -Wl,-z,max-page-size=4096 \
  -Oz -o fcmu_alarm_wait native/fcmu_alarm_wait.c
```

仅 ARM64 + 有效 kernel alarmtimer 才启用；其他设备按状态报告降级。

## 验证与未决事项

Xiaomi pudding / HyperOS 4 / Android 17 实机：内核计时器 1 秒/2 秒试运行成功，观察到维护进程运行 `fcmu_alarm_wait 120`，记录了多次独立定时器到期；GMS 主 PID 未被测试过程重启，FCM 继续连接。已完成零网络中断的回归检查、软重连与误判的模拟测试以及 ZIP 解压校验。

**尚未完成实际整夜深度休眠后的延迟测量、端到端推送验收或电池功耗 A/B 比较。** 每 120 秒唤醒一次可能增加待机功耗，应优先通过实际锁屏过夜记录评估；不要把工具正常运行等同于可以发布稳定版。
